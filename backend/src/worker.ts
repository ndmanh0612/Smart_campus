import type { Pool } from 'pg';
import type { Server as HttpServer } from 'node:http';
import { Server } from 'socket.io';
import { actorForToken } from './auth.ts';
import { camel, id, one, optional, transaction, type Actor, type CampusConfig } from './platform.ts';
import { callback, voidPayment } from './wallet.ts';
import { cancelOrder } from './canteen.ts';
import { gateEvent } from './parking.ts';
import { SimulatedGateProvider } from './providers.ts';
export function attachRealtime(server: HttpServer, pool: Pool, cfg: CampusConfig) {
    const io = new Server(server, { transports: ['websocket'], cors: { origin: cfg.origin, credentials: true }, maxHttpBufferSize: 32768 });
    const ns = io.of('/campus');
    ns.use((socket, next) => { const raw = socket.handshake.auth?.token; if (typeof raw !== 'string') {
        next(Error('UNAUTHORIZED'));
        return;
    } void actorForToken(pool, 'Bearer ' + raw).then(a => { socket.data.actor = a; next(); }, () => next(Error('UNAUTHORIZED'))); });
    ns.on('connection', socket => {
        const a = socket.data.actor as Actor;
        void socket.join('user:' + a.id);
        if (a.roles.some(r => ['ADMIN', 'PARKING_STAFF'].includes(r)))
            void socket.join('staff:parking');
        if (a.roles.some(r => ['ADMIN', 'CANTEEN_STAFF'].includes(r)))
            void socket.join('staff:canteen');
        socket.on('subscribe-attendance', (sessionId: unknown, ack?: ((r: unknown) => void)) => {
            const reply = (result: unknown) => { if (typeof ack === 'function')
                ack(result); };
            void (async () => {
                if (typeof sessionId !== 'string' || sessionId.length !== 36)
                    throw Error('INVALID_ID');
                const current = await actorForToken(pool, 'Bearer ' + socket.handshake.auth.token);
                await transaction(pool, async (db) => {
                    const s = await one(db, 'SELECT section_id FROM attendance_sessions WHERE id=$1', [sessionId]);
                    if (!current.roles.includes('ADMIN') && (!current.lecturerId || !await optional(db, 'SELECT 1 FROM teaching_assignments WHERE section_id=$1 AND lecturer_id=$2', [s.section_id, current.lecturerId])))
                        throw Error('FORBIDDEN');
                });
                await socket.join('attendance:' + sessionId);
                reply({ subscribed: true });
            })().catch(() => reply({ error: 'FORBIDDEN' }));
        });
    });
    async function publish(event: Record<string, any>) {
        // Recheck before outbound delivery so role revocation cannot leave a stale privileged room.
        for (const socket of ns.sockets.values()) {
            try {
                const current = await actorForToken(pool, 'Bearer ' + socket.handshake.auth.token);
                const prior = socket.data.actor as Actor;
                if (JSON.stringify(current.roles) !== JSON.stringify(prior.roles)) {
                    socket.disconnect(true);
                    continue;
                }
                socket.data.actor = current;
                if (event.type.startsWith('attendance.') && socket.rooms.has('attendance:' + event.aggregate_id) && !current.roles.includes('ADMIN')) {
                    const allowed = await transaction(pool, async (db) => optional(db, 'SELECT 1 FROM attendance_sessions s JOIN teaching_assignments a ON a.section_id=s.section_id WHERE s.id=$1 AND a.lecturer_id=$2', [event.aggregate_id, current.lecturerId]));
                    if (!allowed)
                        await socket.leave('attendance:' + event.aggregate_id);
                }
            }
            catch {
                socket.disconnect(true);
            }
        }
        const envelope = camel({ eventId: event.id, type: event.type, aggregateId: event.aggregate_id, occurredAt: event.created_at, source: event.type.includes('attendance') ? 'DEMO' : 'BACKEND', data: event.payload });
        if (event.recipient_user_id)
            ns.to('user:' + event.recipient_user_id).emit(event.type, envelope);
        if (event.type.startsWith('attendance.'))
            ns.to('attendance:' + event.aggregate_id).emit(event.type, envelope);
        if (event.type.startsWith('parking.'))
            ns.to('staff:parking').emit(event.type, envelope);
        if (event.type.startsWith('canteen.'))
            ns.to('staff:canteen').emit(event.type, envelope);
    }
    return { io, publish };
}
export async function runWorkerOnce(pool: Pool, publish?: (event: Record<string, any>) => Promise<void>) {
    const expired = await pool.query("SELECT id FROM campus.orders WHERE status='AWAITING_PAYMENT' AND expires_at<now() LIMIT 20");
    for (const order of expired.rows)
        await transaction(pool, db => cancelOrder(db, null, order.id, 'Đơn hết hạn giữ hàng', true)).catch(() => { });
    await transaction(pool, async (db) => {
        await db.query("UPDATE device_contexts SET status='CANCELLED' WHERE status='OPEN' AND expires_at<now()");
        const expiredPayments = (await db.query("SELECT p.id,p.parking_session_id FROM payments p JOIN parking_quotes q ON q.id=p.quote_id WHERE p.status='AWAITING_CONFIRMATION' AND q.expires_at<now() LIMIT 20")).rows;
        for (const payment of expiredPayments) {
            await one(db, 'SELECT id FROM parking_sessions WHERE id=$1 FOR UPDATE', [payment.parking_session_id]);
            await voidPayment(db, payment.id);
        }
        await db.query('DELETE FROM rate_limit_counters WHERE bucket<$1', [Math.floor(Date.now() / 60000) - 1440]);
    });
    const gates = await pool.query("SELECT * FROM campus.gate_commands WHERE status='QUEUED' OR (status='OPENED' AND expires_at<now()) ORDER BY created_at LIMIT 20");
    for (const cmd of gates.rows) {
        const result = new SimulatedGateProvider().execute(cmd);
        const scenario = cmd.status === 'OPENED' ? 'TIMEOUT_UNKNOWN' : result.status === 'FAILED' ? 'FAIL_BEFORE_OPEN' : 'OPENED';
        await transaction(pool, db => gateEvent(db, null, cmd.id, scenario, 'worker:' + cmd.id + ':' + scenario)).catch(() => { });
    }
    for (let n = 0; n < 20; n++) {
        const event = await transaction(pool, async (db) => {
            const e = await optional(db, "SELECT * FROM outbox_events WHERE published_at IS NULL AND dead_letter_at IS NULL AND (lease_until IS NULL OR lease_until<now()) ORDER BY created_at FOR UPDATE SKIP LOCKED LIMIT 1");
            if (!e)
                return null;
            await db.query("UPDATE outbox_events SET lease_until=now()+interval '30 seconds',attempts=attempts+1 WHERE id=$1", [e.id]);
            return e;
        });
        if (!event)
            break;
        try {
            if (event.type === 'mock.topup.requested')
                await transaction(pool, async (db) => { const order = await one(db, 'SELECT * FROM topup_orders WHERE id=$1', [event.aggregate_id]); await callback(db, { callbackId: 'worker:' + order.id, topupId: order.id, amountPoints: order.amount_points, status: 'SUCCEEDED' }); });
            else if (publish)
                await publish(event);
            await pool.query('UPDATE campus.outbox_events SET published_at=now(),lease_until=NULL WHERE id=$1', [event.id]);
        }
        catch {
            await pool.query("UPDATE campus.outbox_events SET lease_until=now()+interval '5 seconds',dead_letter_at=CASE WHEN attempts>=5 THEN now() ELSE NULL END WHERE id=$1", [event.id]);
        }
    }
}
export function startWorker(pool: Pool, publish?: (event: Record<string, any>) => Promise<void>) {
    let running: Promise<void> | null = null;
    const tick = () => {
        if (running)
            return;
        running = runWorkerOnce(pool, publish).catch(() => { process.stderr.write('{"level":"error","code":"WORKER_FAILED"}\n'); }).finally(() => { running = null; });
    };
    const timer = setInterval(tick, 1000);
    timer.unref();
    tick();
    return async () => { clearInterval(timer); await running; };
}
