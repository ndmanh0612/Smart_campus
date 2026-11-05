import express, { type Request, type Response, type ErrorRequestHandler } from 'express';
import { randomUUID, timingSafeEqual } from 'node:crypto';
import type { Pool } from 'pg';
import { resolve } from 'node:path';
import { existsSync } from 'node:fs';
import { actorForToken, checkPin, login, profile, refresh, revokeSessions, safeError } from './auth.ts';
import { audit, bool, choice, emit, expected, fields, handler, hash, id, integer, mutate, one, optional, passwordHash, points, rateLimit, reject, requirePermission, requireRole, send, str, token, transaction, uuid, type Actor, type CampusConfig, type Db, type Result } from './platform.ts';
import * as wallet from './wallet.ts';
import * as devices from './devices.ts';
import * as parking from './parking.ts';
import * as canteen from './canteen.ts';
import * as attendance from './attendance.ts';
import { normalizePlate } from './providers.ts';
type Context = {
    db: Db;
    a: Actor;
    req: Request;
};
type RouteFn = (c: Context) => Promise<unknown>;
const parkingRoles = ['ADMIN', 'PARKING_STAFF'], canteenRoles = ['ADMIN', 'CANTEEN_STAFF'], lecturerRoles = ['ADMIN', 'LECTURER'];
export function createCampusApp(pool: Pool, cfg: CampusConfig) {
    const app = express();
    app.disable('x-powered-by');
    app.set('trust proxy', false);
    app.use((req, res, next) => {
        res.set({ 'X-Request-Id': randomUUID(), 'Cache-Control': 'no-store', 'X-Content-Type-Options': 'nosniff', 'Referrer-Policy': 'same-origin', 'Content-Security-Policy': "default-src 'self'; script-src 'self' 'wasm-unsafe-eval'; connect-src 'self'; img-src 'self' data: blob:; style-src 'self' 'unsafe-inline'; font-src 'self' data:; worker-src 'self' blob:; frame-ancestors 'none'" });
        const origin = req.get('Origin');
        if (origin && origin !== cfg.origin) {
            res.status(403).json({ error: { code: 'ORIGIN_FORBIDDEN', message: 'Nguồn yêu cầu không được phép.' } });
            return;
        }
        if (origin) {
            res.set('Access-Control-Allow-Origin', origin);
            res.set('Access-Control-Allow-Credentials', 'true');
            res.set('Vary', 'Origin');
        }
        if (req.method === 'OPTIONS') {
            res.set('Access-Control-Allow-Headers', 'Authorization,Content-Type,Idempotency-Key,X-CSRF-Token,X-Client-Type');
            res.set('Access-Control-Allow-Methods', 'GET,POST,PUT,PATCH,DELETE');
            res.sendStatus(204);
            return;
        }
        next();
    });
    app.use(express.json({ limit: '32kb' }));
    app.get('/healthz', (_req, res) => res.json({ status: 'ok', application: 'Smart Campus', environment: cfg.env }));
    app.get('/readyz', handler(async (_req, res) => {
        try {
            const r = await pool.query("SELECT 1 FROM campus.schema_migrations WHERE version='003-operational-indexes'");
            res.status(r.rowCount ? 200 : 503).json({ ready: !!r.rowCount });
        }
        catch {
            res.status(503).json({ ready: false });
        }
    }));
    const cookie = (req: Request, name: string) => { const parts = (req.get('Cookie') ?? '').split(';').map(s => s.trim().split('=')); return parts.find(p => p[0] === name)?.[1]; };
    function sessionResponse(req: Request, res: Response, credentials: Record<string, any>) {
        const native = req.get('X-Client-Type') === 'native';
        if (!native) {
            const csrf = token();
            res.cookie('campus_refresh', credentials.refreshToken, { httpOnly: true, secure: cfg.origin.startsWith('https:'), sameSite: 'strict', path: '/api/v1/auth', maxAge: 7 * 86400000 });
            res.cookie('campus_csrf', csrf, { secure: cfg.origin.startsWith('https:'), sameSite: 'strict', path: '/', maxAge: 7 * 86400000 });
            const { refreshToken, ...rest } = credentials;
            return { ...rest, csrfToken: csrf };
        }
        return credentials;
    }
    app.post('/api/v1/auth/login', handler(async (req, res) => send(res, { data: sessionResponse(req, res, await login(pool, req)) })));
    app.get('/api/v1/auth/csrf', (_req, res) => { const csrf = token(); res.cookie('campus_csrf', csrf, { secure: cfg.origin.startsWith('https:'), sameSite: 'strict', path: '/', maxAge: 7 * 86400000 }); send(res, { data: { csrfToken: csrf } }); });
    app.post('/api/v1/auth/refresh', handler(async (req, res) => {
        await rateLimit(pool, 'refresh:' + req.ip, 30);
        const fromCookie = cookie(req, 'campus_refresh');
        if (fromCookie && (req.get('Origin') !== cfg.origin || !cookie(req, 'campus_csrf') || req.get('X-CSRF-Token') !== cookie(req, 'campus_csrf')))
            reject(403, 'CSRF_REJECTED', 'Yêu cầu làm mới phiên không hợp lệ.');
        const raw = fromCookie ?? str(fields(req.body, ['refreshToken']).refreshToken, 100);
        const result = await refresh(pool, raw);
        if (result.data)
            result.data = sessionResponse(req, res, result.data as Record<string, any>);
        send(res, result);
    }));
    app.post('/api/v1/internal/mock-payment-callbacks', handler(async (req, res) => {
        const supplied = Buffer.from(hash(req.get('Authorization') ?? ''));
        const wanted = Buffer.from(hash('Bearer ' + cfg.mockSecret));
        if (!timingSafeEqual(supplied, wanted))
            reject(401, 'SERVICE_UNAUTHORIZED', 'Thiếu xác thực dịch vụ callback.');
        send(res, { data: await transaction(pool, db => wallet.callback(db, req.body)) });
    }));
    function deviceRoute(path: string, fn: (db: Db, d: Record<string, any>, req: Request) => Promise<unknown>, method: 'get' | 'post' = 'post') {
        app[method]('/api/v1' + path, handler(async (req, res) => {
            const d = await transaction(pool, db => devices.deviceAuth(db, req.get('Authorization') ?? ''));
            await rateLimit(pool, 'device:' + d.id, 120);
            if (method === 'get') {
                send(res, { data: await transaction(pool, db => fn(db, d, req)) });
                return;
            }
            const key = path === '/device-events' ? (req.body as Record<string, unknown>)?.eventId : req.get('Idempotency-Key');
            const result = await mutate(pool, 'device:' + d.id + ':' + path, key, req.body, async (db) => { const current = await one(db, 'SELECT * FROM devices WHERE id=$1 AND active FOR UPDATE', [d.id]); const output = await fn(db, current, req); return path === '/device-events' ? output as Result : { data: output }; });
            send(res, result);
        }));
    }
    deviceRoute('/device/config', (db, d) => devices.deviceConfig(db, d), 'get');
    deviceRoute('/device/config-ack', async (db, d, req) => {
        const b = fields(req.body, ['deviceId', 'configVersion']);
        if (uuid(b.deviceId) !== d.id || integer(b.configVersion) !== d.config_version)
            reject(409, 'CONFIG_MISMATCH', 'Phiên bản cấu hình không khớp.');
        await db.query('UPDATE devices SET ack_version=config_version,last_seen_at=now() WHERE id=$1', [d.id]);
        return { acknowledged: true };
    });
    deviceRoute('/device/heartbeat', async (db, d, req) => { fields(req.body, ['configVersion', 'firmwareVersion']); return devices.deviceConfig(db, d); });
    deviceRoute('/device/challenges', (db, d, req) => devices.challenge(db, d, req.body));
    deviceRoute('/device-events', (db, d, req) => devices.scan(db, d, req.body, cfg));
    deviceRoute('/device-events/:eventId', async (db, d, req) => one(db, 'SELECT response,http_status FROM device_events WHERE device_id=$1 AND event_id=$2', [d.id, uuid(req.params.eventId)]), 'get');
    deviceRoute('/device/pending-actions', async (db, d) => (await db.query("SELECT c.id,c.purpose,c.status,c.expires_at,a.id AS identity_assertion_id FROM device_contexts c LEFT JOIN identity_assertions a ON a.context_id=c.id WHERE c.device_id=$1 ORDER BY c.created_at DESC LIMIT 5", [d.id])).rows, 'get');
    deviceRoute('/device/actions/:id', (db, d, req) => devices.deviceAction(db, d, uuid(req.params.id)), 'get');
    app.use('/api/v1', (req, res, next) => { void (async () => { const a = await actorForToken(pool, req.get('Authorization') ?? ''); res.locals.actor = a; await rateLimit(pool, 'user:' + a.id, 240); })().then(() => next(), next); });
    function read(path: string, roles: string[] | null, fn: RouteFn) {
        app.get('/api/v1' + path, handler(async (req, res) => {
            const a = res.locals.actor as Actor;
            if (roles)
                requireRole(a, ...roles);
            send(res, { data: await transaction(pool, db => fn({ db, a, req })) });
        }));
    }
    function write(path: string, roles: string[] | null, fn: RouteFn, method: 'post' | 'put' | 'patch' | 'delete' = 'post', raw = false) {
        app[method]('/api/v1' + path, handler(async (req, res) => {
            const a = res.locals.actor as Actor;
            if (roles)
                requireRole(a, ...roles);
            const result = await mutate(pool, 'user:' + a.id + ':' + req.method + ':' + req.path, req.get('Idempotency-Key'), req.body, async (db) => { if (req.path.endsWith('/me/wallet-pin') && Date.now() - a.authenticatedAt.getTime() > 300000)
                reject(403, 'RECENT_AUTH_REQUIRED', 'Hãy đăng nhập lại trước khi thay đổi PIN.'); const data = await fn({ db, a, req }); await audit(db, a, 'API_MUTATION', null, undefined, { method: req.method, path: req.path }); return raw ? data as Result : { data }; });
            send(res, result);
        }));
    }
    read('/me', null, ({ db, a }) => profile(db, a));
    write('/auth/logout', null, async ({ db, a }) => { await revokeSessions(db, a); return { loggedOut: true }; });
    write('/me', null, async ({ db, a, req }) => { const b = fields(req.body, ['name']); await db.query('UPDATE users SET name=$2 WHERE id=$1', [a.id, str(b.name, 120)]); return profile(db, a); }, 'patch');
    read('/me/notifications', null, async ({ db, a }) => (await db.query('SELECT * FROM notifications WHERE recipient_user_id=$1 ORDER BY created_at DESC LIMIT 100', [a.id])).rows);
    write('/me/notifications/:id/read', null, async ({ db, a, req }) => { await db.query('UPDATE notifications SET read_at=now() WHERE id=$1 AND recipient_user_id=$2', [uuid(req.params.id), a.id]); return { read: true }; });
    read('/me/cards', ['STUDENT'], async ({ db, a }) => (await db.query('SELECT id,status,expires_at,created_at FROM rfid_cards WHERE student_id=$1 ORDER BY created_at DESC', [a.studentId])).rows);
    write('/me/cards/:id/report-lost', ['STUDENT'], async ({ db, a, req }) => { const b = fields(req.body, ['reason']); const card = await one(db, 'SELECT * FROM rfid_cards WHERE id=$1 AND student_id=$2 FOR UPDATE', [uuid(req.params.id), a.studentId]); await db.query("UPDATE rfid_cards SET status='LOST',revoked_at=now() WHERE id=$1", [card.id]); await db.query('UPDATE payment_approvals SET consumed_at=now() WHERE payment_id IN(SELECT p.id FROM payments p JOIN identity_assertions a ON a.id=p.identity_assertion_id WHERE a.card_id=$1) AND consumed_at IS NULL', [card.id]); await audit(db, a, 'CARD_LOST', card.id, str(b.reason, 1000, 5)); return { id: card.id, status: 'LOST' }; });
    write('/enrollment-contexts', ['ADMIN'], async ({ db, a, req }) => { requirePermission(a, 'device.configure'); const b = fields(req.body, ['studentId', 'deviceId']); return devices.createContext(db, uuid(b.deviceId), 'ENROLLMENT', uuid(b.studentId)); });
    write('/rfid-cards', ['ADMIN'], async ({ db, a, req }) => {
        const b = fields(req.body, ['enrollmentAssertionId', 'studentId', 'replaceCardId'], ['enrollmentAssertionId', 'studentId']);
        const identity = await devices.consumeIdentity(db, uuid(b.enrollmentAssertionId), 'ENROLLMENT', uuid(b.studentId));
        if (identity.source !== 'REAL' || !identity.credential_hmac)
            reject(422, 'REAL_RFID_REQUIRED', 'Phải quét RFID thật để cấp thẻ.');
        if (b.replaceCardId) {
            const old = await one(db, 'SELECT id FROM rfid_cards WHERE id=$1 AND student_id=$2 FOR UPDATE', [uuid(b.replaceCardId), identity.student_id]);
            await db.query("UPDATE rfid_cards SET status='REVOKED',revoked_at=now() WHERE id=$1", [old.id]);
        }
        const cardId = id();
        await db.query("INSERT INTO rfid_cards(id,student_id,uid_hmac,status) VALUES($1,$2,$3,'ACTIVE')", [cardId, identity.student_id, identity.credential_hmac]);
        await db.query('UPDATE identity_assertions SET resource_id=$2 WHERE id=$1', [identity.id, cardId]);
        await audit(db, a, 'CARD_ISSUED', cardId);
        return { id: cardId, status: 'ACTIVE' };
    });
    write('/rfid-cards/:id/revoke', ['ADMIN'], async ({ db, a, req }) => { const b = fields(req.body, ['reason']); await one(db, "UPDATE rfid_cards SET status='REVOKED',revoked_at=now() WHERE id=$1 RETURNING id", [uuid(req.params.id)]); await audit(db, a, 'CARD_REVOKED', uuid(req.params.id), str(b.reason, 1000, 5)); return { revoked: true }; });
    read('/me/vehicles', ['STUDENT'], async ({ db, a }) => (await db.query('SELECT v.*,a.active AS authorized,a.valid_to FROM vehicles v JOIN vehicle_authorizations a ON a.vehicle_id=v.id WHERE a.student_id=$1', [a.studentId])).rows);
    write('/me/vehicles', ['STUDENT'], async ({ db, a, req }) => { const b = fields(req.body, ['plate', 'vehicleType']); const vehicleId = id(), raw = str(b.plate, 30); await db.query('INSERT INTO vehicles VALUES($1,$2,$3,$4,false)', [vehicleId, normalizePlate(raw), raw, choice(b.vehicleType, ['MOTORCYCLE', 'CAR', 'BICYCLE'] as const)]); await db.query('INSERT INTO vehicle_authorizations(vehicle_id,student_id,active) VALUES($1,$2,false)', [vehicleId, a.studentId]); await audit(db, a, 'VEHICLE_REGISTRATION_REQUEST', vehicleId); return { id: vehicleId, approvalRequired: true }; });
    write('/vehicle-authorizations', ['ADMIN'], async ({ db, a, req }) => { const b = fields(req.body, ['vehicleId', 'studentId', 'reason']); await one(db, 'UPDATE vehicles SET active=true WHERE id=$1 RETURNING id', [uuid(b.vehicleId)]); await db.query('INSERT INTO vehicle_authorizations(vehicle_id,student_id,active) VALUES($1,$2,true) ON CONFLICT(vehicle_id,student_id) DO UPDATE SET active=true', [b.vehicleId, uuid(b.studentId)]); await audit(db, a, 'VEHICLE_AUTHORIZED', b.vehicleId as string, str(b.reason, 1000, 5)); return { authorized: true }; });
    read('/me/biometric-consents', ['STUDENT'], async ({ db, a }) => (await db.query('SELECT * FROM biometric_consents WHERE student_id=$1 ORDER BY granted_at DESC', [a.studentId])).rows);
    read('/me/biometric-profiles', ['STUDENT'], async ({ db, a }) => (await db.query('SELECT id,purpose,source,status,erased_at,created_at FROM biometric_profiles WHERE student_id=$1 ORDER BY created_at DESC', [a.studentId])).rows);
    write('/me/biometric-consents', ['STUDENT'], async ({ db, a, req }) => {
        const b = fields(req.body, ['purpose', 'policyVersion', 'explicitConsent']);
        if (b.explicitConsent !== true)
            reject(422, 'EXPLICIT_CONSENT_REQUIRED', 'Cần đồng ý rõ ràng.');
        const student = await one(db, 'SELECT synthetic FROM students WHERE id=$1', [a.studentId]);
        if (!student.synthetic)
            reject(422, 'DEMO_FIXTURE_ONLY', 'MVP không thu sinh trắc học thật.');
        const consentId = id(), purpose = choice(b.purpose, ['PARKING', 'CANTEEN', 'ATTENDANCE'] as const);
        await db.query("INSERT INTO biometric_consents(id,student_id,purpose,policy_version,source) VALUES($1,$2,$3,$4,'DEMO')", [consentId, a.studentId, purpose, str(b.policyVersion, 100)]);
        await audit(db, a, 'CONSENT_GRANTED', consentId);
        return { id: consentId, source: 'DEMO' };
    });
    write('/me/biometric-consents/:id/revoke', ['STUDENT'], async ({ db, a, req }) => { const consent = await one(db, 'UPDATE biometric_consents SET revoked_at=now() WHERE id=$1 AND student_id=$2 RETURNING id', [uuid(req.params.id), a.studentId]); await db.query("UPDATE biometric_profiles SET status='ERASED',erased_at=now() WHERE consent_id=$1", [consent.id]); await audit(db, a, 'CONSENT_REVOKED', consent.id); return { revoked: true }; });
    write('/me/biometric-profiles/enrollment-requests', ['STUDENT'], async ({ db, a, req }) => { const b = fields(req.body, ['consentId']); const consent = await one(db, "SELECT * FROM biometric_consents WHERE id=$1 AND student_id=$2 AND revoked_at IS NULL AND source='DEMO'", [uuid(b.consentId), a.studentId]); const profileId = id(); await db.query("INSERT INTO biometric_profiles(id,student_id,consent_id,purpose,source,model_version,status) VALUES($1,$2,$3,$4,'DEMO','demo-v1','ACTIVE')", [profileId, a.studentId, consent.id, consent.purpose]); return { id: profileId, source: 'DEMO', containsRealBiometrics: false }; });
    write('/me/biometric-profiles/:id', ['STUDENT'], async ({ db, a, req }) => { await one(db, "UPDATE biometric_profiles SET status='ERASED',erased_at=now() WHERE id=$1 AND student_id=$2 RETURNING id", [uuid(req.params.id), a.studentId]); await audit(db, a, 'BIOMETRIC_ERASED', uuid(req.params.id)); return { status: 'ERASED' }; }, 'delete');
    write('/me/wallet-pin', ['STUDENT'], async ({ db, a, req }) => {
        const b = fields(req.body, ['oldPin', 'newPin'], ['newPin']);
        if (await optional(db, 'SELECT 1 FROM wallet_security_settings WHERE student_id=$1', [a.studentId])) {
            const err = await checkPin(db, a, b.oldPin);
            if (err)
                return err;
        }
        const pin = str(b.newPin, 12, 6);
        if (!/^\d{6,12}$/.test(pin))
            reject(400, 'INVALID_PIN', 'PIN mới cần 6–12 chữ số.');
        await db.query('INSERT INTO wallet_security_settings(student_id,pin_hash) VALUES($1,$2) ON CONFLICT(student_id) DO UPDATE SET pin_hash=EXCLUDED.pin_hash,pin_version=wallet_security_settings.pin_version+1,failed_count=0,locked_until=NULL', [a.studentId, await passwordHash(pin)]);
        await audit(db, a, 'PIN_CHANGED', a.studentId);
        return { data: { changed: true } };
    }, 'put', true);
    read('/me/wallet', ['STUDENT'], ({ db, a }) => wallet.balance(db, a.studentId!));
    read('/me/wallet/ledger', ['STUDENT'], async ({ db, a }) => (await db.query('SELECT e.*,t.type,t.original_transaction_id FROM wallet_ledger_entries e JOIN wallet_transactions t ON t.id=e.transaction_id JOIN wallets w ON w.account_id=e.account_id WHERE w.student_id=$1 ORDER BY e.created_at DESC,e.id DESC LIMIT 100', [a.studentId])).rows);
    read('/me/wallet/transactions', ['STUDENT'], async ({ db, a }) => (await db.query('SELECT * FROM wallet_transactions WHERE student_id=$1 ORDER BY created_at DESC LIMIT 100', [a.studentId])).rows);
    write('/me/topups', ['STUDENT'], ({ db, a, req }) => wallet.topup(db, a, req.body));
    read('/me/topups', ['STUDENT'], async ({ db, a }) => (await db.query('SELECT t.* FROM topup_orders t JOIN wallets w ON w.id=t.wallet_id WHERE w.student_id=$1 ORDER BY created_at DESC LIMIT 100', [a.studentId])).rows);
    read('/me/topups/:id', ['STUDENT'], ({ db, a, req }) => one(db, 'SELECT t.* FROM topup_orders t JOIN wallets w ON w.id=t.wallet_id WHERE t.id=$1 AND w.student_id=$2', [uuid(req.params.id), a.studentId]));
    read('/me/payment-requests', ['STUDENT'], async ({ db, a }) => (await db.query("SELECT p.*,coalesce(o.version,s.version) AS source_version,o.expires_at AS order_expires_at FROM payments p LEFT JOIN orders o ON o.id=p.order_id LEFT JOIN parking_sessions s ON s.id=p.parking_session_id WHERE p.student_id=$1 AND p.status='AWAITING_CONFIRMATION' ORDER BY p.created_at DESC LIMIT 100", [a.studentId])).rows);
    read('/me/payments/:id', ['STUDENT'], ({ db, a, req }) => one(db, 'SELECT * FROM payments WHERE id=$1 AND student_id=$2', [uuid(req.params.id), a.studentId]));
    write('/me/payments/:id/approvals', ['STUDENT'], ({ db, a, req }) => wallet.approve(db, a, uuid(req.params.id), req.body), 'post', true);
    write('/refunds', canteenRoles, ({ db, a, req }) => wallet.refund(db, a, req.body));
    read('/refunds', canteenRoles, async ({ db }) => (await db.query('SELECT * FROM refunds ORDER BY created_at DESC LIMIT 100')).rows);
    write('/admin/wallet-adjustments', ['ADMIN'], async ({ db, a, req }) => {
        requirePermission(a, 'wallet.adjust');
        const b = fields(req.body, ['studentId', 'deltaPoints', 'reason']);
        const delta = str(b.deltaPoints, 14);
        if (!/^-?[1-9][0-9]{0,8}$/.test(delta))
            reject(400, 'INVALID_AMOUNT', 'Điều chỉnh point không hợp lệ.');
        const studentId = uuid(b.studentId), adjustmentId = id(), reason = str(b.reason, 1000, 5);
        await db.query('INSERT INTO wallet_adjustments(id,student_id,delta_points,reason,actor_id) VALUES($1,$2,$3,$4,$5)', [adjustmentId, studentId, delta, reason, a.id]);
        const txId = await wallet.post(db, 'ADMIN_ADJUSTMENT', studentId, (BigInt(delta) < 0n ? -BigInt(delta) : BigInt(delta)).toString(), { adjustment: adjustmentId });
        await audit(db, a, 'WALLET_ADJUSTED', adjustmentId, reason);
        return { id: adjustmentId, transactionId: txId };
    });
    read('/admin/wallet-reconciliation', ['ADMIN'], async ({ db }) => (await db.query('SELECT a.id,a.kind,a.balance_points,coalesce(sum(e.delta_points),0)::text AS ledger_points FROM ledger_accounts a LEFT JOIN wallet_ledger_entries e ON e.account_id=a.id GROUP BY a.id HAVING a.balance_points<>coalesce(sum(e.delta_points),0)')).rows);
    read('/parking/lots', parkingRoles, async ({ db }) => (await db.query('SELECT * FROM parking_lots ORDER BY code')).rows);
    read('/parking/sessions', parkingRoles, async ({ db }) => (await db.query('SELECT s.*,st.student_code,v.normalized_plate FROM parking_sessions s JOIN students st ON st.id=s.student_id JOIN vehicles v ON v.id=s.vehicle_id ORDER BY s.created_at DESC LIMIT 100')).rows);
    read('/parking/sessions/:id', parkingRoles, async ({ db, req }) => { const s = await one(db, 'SELECT * FROM parking_sessions WHERE id=$1', [uuid(req.params.id)]); return { ...s, payments: (await db.query('SELECT p.*,a.id AS approval_id FROM payments p LEFT JOIN payment_approvals a ON a.payment_id=p.id AND a.consumed_at IS NULL AND a.expires_at>now() WHERE p.parking_session_id=$1 ORDER BY p.created_at DESC', [s.id])).rows }; });
    read('/parking/gate-commands', parkingRoles, async ({ db }) => (await db.query('SELECT * FROM gate_commands ORDER BY created_at DESC LIMIT 100')).rows);
    write('/parking/entry-contexts', parkingRoles, async ({ db, req }) => {
        const b = fields(req.body, ['lotId', 'deviceId']);
        const d = await one(db, 'SELECT parking_lot_id FROM devices WHERE id=$1', [uuid(b.deviceId)]);
        if (d.parking_lot_id !== uuid(b.lotId))
            reject(422, 'DEVICE_LOT_MISMATCH', 'Thiết bị không thuộc bãi xe.');
        return devices.createContext(db, b.deviceId as string, 'PARKING_ENTRY', b.lotId as string);
    });
    write('/parking/entries', parkingRoles, ({ db, a, req }) => parking.entry(db, a, req.body));
    write('/parking/sessions/:id/exit-contexts', parkingRoles, async ({ db, req }) => {
        const b = fields(req.body, ['deviceId', 'expectedVersion']);
        const session = await one(db, 'SELECT * FROM parking_sessions WHERE id=$1', [uuid(req.params.id)]);
        expected(session.version, b.expectedVersion);
        if (session.status !== 'ACTIVE')
            reject(409, 'PARKING_STATE', 'Phiên không ở trạng thái ACTIVE.');
        const d = await one(db, 'SELECT parking_lot_id FROM devices WHERE id=$1', [uuid(b.deviceId)]);
        if (d.parking_lot_id !== session.lot_id)
            reject(422, 'DEVICE_LOT_MISMATCH', 'Sai bãi xe.');
        return devices.createContext(db, b.deviceId as string, 'PARKING_EXIT', session.id);
    });
    write('/parking/sessions/:id/exit-quotes', parkingRoles, ({ db, a, req }) => parking.exitQuote(db, a, uuid(req.params.id), req.body));
    write('/parking/sessions/:id/exit-authorizations', parkingRoles, ({ db, a, req }) => parking.exitAuthorize(db, a, uuid(req.params.id), req.body));
    write('/parking/sessions/:id/exception-resolutions', parkingRoles, ({ db, a, req }) => parking.resolveException(db, a, uuid(req.params.id), req.body));
    write('/parking/gate-commands/:id/passage-confirmations', parkingRoles, async ({ db, a, req }) => { const b = fields(req.body, ['reason', 'providerEventId']); str(b.reason, 1000, 5); return parking.gateEvent(db, a, uuid(req.params.id), 'PASSAGE', str(b.providerEventId, 128)); }, 'post', true);
    write('/parking/ocr-observations/:id/corrections', parkingRoles, async ({ db, a, req }) => { const b = fields(req.body, ['correctedPlate', 'reason']); const observation = await one(db, 'SELECT id FROM ocr_observations WHERE id=$1', [uuid(req.params.id)]); const correctedPlate = normalizePlate(str(b.correctedPlate, 30)), reason = str(b.reason, 1000, 5); const correctionId = id(); await db.query('INSERT INTO ocr_corrections VALUES($1,$2,$3,$4,$5,now())', [correctionId, observation.id, correctedPlate, reason, a.id]); await audit(db, a, 'OCR_CORRECTED', observation.id, reason, { correctedPlate }); return { id: correctionId, correctedPlate }; });
    read('/me/parking-sessions', ['STUDENT'], async ({ db, a }) => (await db.query('SELECT * FROM parking_sessions WHERE student_id=$1 ORDER BY created_at DESC LIMIT 100', [a.studentId])).rows);
    read('/canteen/products', null, async ({ db }) => (await db.query('SELECT p.*,c.name AS category_name,i.on_hand,i.reserved,i.on_hand-i.reserved AS available FROM products p JOIN product_categories c ON c.id=p.category_id JOIN inventory i ON i.product_id=p.id ORDER BY p.name LIMIT 100')).rows);
    read('/canteen/categories', null, async ({ db }) => (await db.query('SELECT * FROM product_categories ORDER BY name')).rows);
    write('/canteen/categories', canteenRoles, async ({ db, req }) => { const b = fields(req.body, ['name']); const categoryId = id(); await db.query('INSERT INTO product_categories VALUES($1,$2)', [categoryId, str(b.name, 100)]); return { id: categoryId }; });
    write('/canteen/products', canteenRoles, async ({ db, a, req }) => { const b = fields(req.body, ['categoryId', 'sku', 'name', 'pricePoints', 'initialStock']); const productId = id(); await db.query('INSERT INTO products(id,category_id,sku,name,price_points) VALUES($1,$2,$3,$4,$5)', [productId, uuid(b.categoryId), str(b.sku, 50), str(b.name, 120), points(b.pricePoints)]); const stock = integer(b.initialStock, 0); await db.query('INSERT INTO inventory(product_id,on_hand) VALUES($1,$2)', [productId, stock]); await audit(db, a, 'PRODUCT_CREATED', productId); return { id: productId }; });
    write('/canteen/products/:id', canteenRoles, async ({ db, a, req }) => { const b = fields(req.body, ['name', 'pricePoints', 'active', 'expectedVersion']); const product = await one(db, 'SELECT * FROM products WHERE id=$1 FOR UPDATE', [uuid(req.params.id)]); expected(product.price_version, b.expectedVersion); await db.query('UPDATE products SET name=$2,price_points=$3,active=$4,price_version=price_version+1 WHERE id=$1', [product.id, str(b.name, 120), points(b.pricePoints), bool(b.active)]); await audit(db, a, 'PRODUCT_CHANGED', product.id); return one(db, 'SELECT * FROM products WHERE id=$1', [product.id]); }, 'patch');
    write('/canteen/inventory-adjustments', canteenRoles, async ({ db, a, req }) => {
        const b = fields(req.body, ['productId', 'delta', 'reason']);
        const delta = integer(b.delta, -100000, 100000);
        if (delta === 0)
            reject(400, 'ZERO_ADJUSTMENT', 'Điều chỉnh kho không được bằng 0.');
        const productId = uuid(b.productId), reason = str(b.reason, 1000, 5);
        await one(db, 'UPDATE inventory SET on_hand=on_hand+$2 WHERE product_id=$1 RETURNING *', [productId, delta]);
        await db.query("INSERT INTO inventory_movements(id,product_id,kind,quantity_delta,reason) VALUES($1,$2,'ADJUST',$3,$4)", [id(), productId, delta, reason]);
        await audit(db, a, 'STOCK_ADJUSTED', productId, reason);
        return { adjusted: true };
    });
    read('/canteen/inventory-movements', canteenRoles, async ({ db }) => (await db.query('SELECT * FROM inventory_movements ORDER BY created_at DESC LIMIT 100')).rows);
    write('/canteen/orders', canteenRoles, ({ db, a, req }) => canteen.createOrder(db, a, req.body));
    read('/canteen/orders', canteenRoles, async ({ db }) => (await db.query('SELECT * FROM orders ORDER BY created_at DESC LIMIT 100')).rows);
    read('/canteen/orders/:id', canteenRoles, async ({ db, req }) => { const order = await one(db, 'SELECT * FROM orders WHERE id=$1', [uuid(req.params.id)]); return { ...order, items: (await db.query('SELECT i.*,p.name FROM order_items i JOIN products p ON p.id=i.product_id WHERE order_id=$1', [order.id])).rows, payments: (await db.query('SELECT p.*,a.id AS approval_id FROM payments p LEFT JOIN payment_approvals a ON a.payment_id=p.id AND a.consumed_at IS NULL AND a.expires_at>now() WHERE p.order_id=$1', [order.id])).rows }; });
    write('/canteen/orders/:id/checkout-contexts', canteenRoles, async ({ db, req }) => {
        const b = fields(req.body, ['deviceId', 'expectedVersion']);
        const order = await one(db, 'SELECT * FROM orders WHERE id=$1', [uuid(req.params.id)]);
        expected(order.version, b.expectedVersion);
        if (order.status !== 'AWAITING_PAYMENT' || new Date(order.expires_at) < new Date())
            reject(422, 'RESERVATION_EXPIRED', 'Đơn đã hết hạn.');
        return devices.createContext(db, uuid(b.deviceId), 'CANTEEN', order.id);
    });
    write('/canteen/orders/:id/identify', canteenRoles, ({ db, a, req }) => canteen.identify(db, a, uuid(req.params.id), req.body));
    write('/canteen/orders/:id/payments', canteenRoles, ({ db, a, req }) => canteen.checkout(db, a, uuid(req.params.id), req.body));
    write('/canteen/orders/:id/cancel', canteenRoles, ({ db, a, req }) => canteen.cancelOrder(db, a, uuid(req.params.id), str(fields(req.body, ['reason']).reason, 1000, 5)));
    read('/me/canteen-orders', ['STUDENT'], async ({ db, a }) => (await db.query('SELECT * FROM orders WHERE student_id=$1 ORDER BY created_at DESC LIMIT 100', [a.studentId])).rows);
    registerAcademic(read, write);
    write('/device-contexts/:id/cancel', ['ADMIN', 'PARKING_STAFF', 'CANTEEN_STAFF', 'LECTURER'], async ({ db, a, req }) => { const b = fields(req.body, ['reason']); const c = await one(db, 'SELECT * FROM device_contexts WHERE id=$1 FOR UPDATE', [uuid(req.params.id)]); requireRole(a, ...(c.purpose === 'ENROLLMENT' ? ['ADMIN'] : c.purpose === 'CANTEEN' ? canteenRoles : c.purpose === 'ATTENDANCE' ? lecturerRoles : parkingRoles)); if (c.status !== 'OPEN')
        reject(409, 'CONTEXT_STATE', 'Lần xác thực đã được sử dụng; hãy xử lý nghiệp vụ tương ứng.'); await db.query("UPDATE device_contexts SET status='CANCELLED' WHERE id=$1", [c.id]); await audit(db, a, 'DEVICE_CONTEXT_CANCELLED', c.id, str(b.reason, 1000, 5)); return { cancelled: true }; });
    if (cfg.simulator)
        registerSimulation(read, write);
    registerAdmin(read, write);
    read('/dashboard', null, async ({ db, a }) => {
        if (a.studentId)
            return { wallet: await wallet.balance(db, a.studentId), notifications: (await db.query('SELECT count(*)::integer AS count FROM notifications WHERE recipient_user_id=$1 AND read_at IS NULL', [a.id])).rows[0].count };
        return { parking: (await db.query("SELECT status,count(*)::integer AS count FROM parking_sessions GROUP BY status")).rows, orders: (await db.query('SELECT status,count(*)::integer AS count FROM orders GROUP BY status')).rows, attendance: (await db.query('SELECT status,count(*)::integer AS count FROM attendance_sessions GROUP BY status')).rows };
    });
    const web = resolve(import.meta.dirname, '../../flutter/app/build/web');
    if (existsSync(resolve(web, 'index.html'))) {
        app.use(express.static(web, { index: false }));
        app.get(['/', '/app'], (_req, res) => res.sendFile(resolve(web, 'index.html')));
    }
    app.use((_req, res) => send(res, { status: 404, error: { code: 'NOT_FOUND', message: 'Không tìm thấy đường dẫn.' } }));
    const errors: ErrorRequestHandler = (error, _req, res, _next) => {
        const e = safeError(error);
        if (e.status === 429)
            res.set('Retry-After', '60');
        if (e.status >= 500)
            process.stderr.write(JSON.stringify({ level: 'error', requestId: res.getHeader('X-Request-Id'), code: (error as {
                    code?: string;
                }).code ?? 'UNKNOWN' }) + '\n');
        send(res, { status: e.status, error: { code: e.code, message: e.message, details: e.details } });
    };
    app.use(errors);
    return app;
}
type Read = (path: string, roles: string[] | null, fn: RouteFn) => void;
type Write = (path: string, roles: string[] | null, fn: RouteFn, method?: 'post' | 'put' | 'patch' | 'delete', raw?: boolean) => void;
function registerAcademic(read: Read, write: Write) {
    read('/lecturer/class-sections', lecturerRoles, async ({ db, a }) => (await db.query('SELECT c.*,s.id AS schedule_id,s.starts_at,s.ends_at,s.classroom_id FROM class_sections c JOIN schedules s ON s.section_id=c.id WHERE $1::boolean OR EXISTS(SELECT 1 FROM teaching_assignments WHERE section_id=c.id AND lecturer_id=$2) ORDER BY s.starts_at DESC LIMIT 100', [a.roles.includes('ADMIN'), a.lecturerId])).rows);
    read('/attendance/sessions', lecturerRoles, async ({ db, a }) => (await db.query('SELECT s.* FROM attendance_sessions s WHERE $1::boolean OR EXISTS(SELECT 1 FROM teaching_assignments WHERE section_id=s.section_id AND lecturer_id=$2) ORDER BY opened_at DESC NULLS LAST LIMIT 100', [a.roles.includes('ADMIN'), a.lecturerId])).rows);
    write('/attendance/sessions', lecturerRoles, ({ db, a, req }) => attendance.createSession(db, a, req.body));
    write('/attendance/sessions/:id/open', lecturerRoles, ({ db, a, req }) => attendance.openSession(db, a, uuid(req.params.id), req.body));
    write('/attendance/sessions/:id/close', lecturerRoles, ({ db, a, req }) => attendance.closeSession(db, a, uuid(req.params.id), req.body));
    write('/attendance/sessions/:id/cancel', lecturerRoles, ({ db, a, req }) => attendance.closeSession(db, a, uuid(req.params.id), req.body, true));
    read('/attendance/sessions/:id', lecturerRoles, async ({ db, a, req }) => { const s = await one(db, 'SELECT * FROM attendance_sessions WHERE id=$1', [uuid(req.params.id)]); await attendance.teachingScope(db, a, s.section_id); return s; });
    read('/attendance/sessions/:id/records', lecturerRoles, async ({ db, a, req }) => { const s = await one(db, 'SELECT * FROM attendance_sessions WHERE id=$1', [uuid(req.params.id)]); await attendance.teachingScope(db, a, s.section_id); return (await db.query('SELECT r.*,u.name,st.student_code FROM attendance_records r JOIN students st ON st.id=r.student_id JOIN users u ON u.id=st.user_id WHERE r.session_id=$1 ORDER BY st.student_code', [s.id])).rows; });
    write('/attendance/records/:id', lecturerRoles, ({ db, a, req }) => attendance.correctRecord(db, a, uuid(req.params.id), req.body), 'patch');
    read('/me/attendance', ['STUDENT'], async ({ db, a }) => (await db.query('SELECT r.*,s.status AS session_status FROM attendance_records r JOIN attendance_sessions s ON s.id=r.session_id WHERE r.student_id=$1 ORDER BY received_at DESC LIMIT 100', [a.studentId])).rows);
    write('/attendance/adjustment-requests', ['STUDENT'], async ({ db, a, req }) => { const b = fields(req.body, ['recordId', 'requestedStatus', 'reason']); const r = await one(db, 'SELECT id FROM attendance_records WHERE id=$1 AND student_id=$2', [uuid(b.recordId), a.studentId]); const requestId = id(); await db.query("INSERT INTO attendance_adjustment_requests(id,record_id,student_id,requested_status,reason,status) VALUES($1,$2,$3,$4,$5,'PENDING')", [requestId, r.id, a.studentId, choice(b.requestedStatus, ['PRESENT', 'LATE', 'EXCUSED'] as const), str(b.reason, 1000, 5)]); return { id: requestId }; });
    read('/attendance/adjustment-requests', lecturerRoles, async ({ db, a }) => (await db.query('SELECT q.* FROM attendance_adjustment_requests q JOIN attendance_records r ON r.id=q.record_id JOIN attendance_sessions s ON s.id=r.session_id WHERE $1::boolean OR EXISTS(SELECT 1 FROM teaching_assignments WHERE section_id=s.section_id AND lecturer_id=$2) ORDER BY q.created_at DESC LIMIT 100', [a.roles.includes('ADMIN'), a.lecturerId])).rows);
    write('/attendance/adjustment-requests/:id/decisions', lecturerRoles, async ({ db, a, req }) => {
        const b = fields(req.body, ['decision', 'reason']);
        const q = await one(db, 'SELECT * FROM attendance_adjustment_requests WHERE id=$1 FOR UPDATE', [uuid(req.params.id)]);
        if (q.status !== 'PENDING')
            reject(409, 'REQUEST_DECIDED', 'Yêu cầu đã được xử lý.');
        const r = await one(db, 'SELECT r.*,s.section_id FROM attendance_records r JOIN attendance_sessions s ON s.id=r.session_id WHERE r.id=$1', [q.record_id]);
        await attendance.teachingScope(db, a, r.section_id);
        const decision = choice(b.decision, ['APPROVED', 'REJECTED'] as const), reason = str(b.reason, 1000, 5);
        if (decision === 'APPROVED')
            await attendance.correctRecord(db, a, r.id, { status: q.requested_status, reason, expectedVersion: r.version });
        await db.query('UPDATE attendance_adjustment_requests SET status=$2 WHERE id=$1', [q.id, decision]);
        return { id: q.id, status: decision };
    });
    read('/attendance/sessions/:id/report', lecturerRoles, async ({ db, a, req }) => { const s = await one(db, 'SELECT * FROM attendance_sessions WHERE id=$1', [uuid(req.params.id)]); await attendance.teachingScope(db, a, s.section_id); const rows = (await db.query('SELECT st.student_code,u.name,r.status,r.source FROM attendance_records r JOIN students st ON st.id=r.student_id JOIN users u ON u.id=st.user_id WHERE r.session_id=$1 ORDER BY st.student_code', [s.id])).rows; return { fileName: 'diem-danh.csv', content: 'Ma sinh vien,Ho ten,Trang thai,Nguon\r\n' + rows.map(r => [r.student_code, r.name, r.status, r.source].map(attendance.csvCell).join(',')).join('\r\n') }; });
}
function registerSimulation(read: Read, write: Write) {
    const simRoles = ['ADMIN', 'LECTURER', 'PARKING_STAFF', 'CANTEEN_STAFF'];
    read('/simulator/status', simRoles, async ({ db, a }) => { requirePermission(a, 'simulator.use'); return { modes: { rfid: 'REAL', face: 'DEMO', liveness: 'DEMO', ocr: 'DEMO', camera: 'DEMO', gate: 'SIMULATOR', payment: 'MOCK' }, devices: (await db.query('SELECT id,name,kind,role,config_version,ack_version,last_seen_at,last_uid_mask,active FROM devices ORDER BY name')).rows }; });
    read('/simulator/students', simRoles, async ({ db, a }) => { requirePermission(a, 'simulator.use'); return (await db.query('SELECT s.id,s.student_code,u.name FROM students s JOIN users u ON u.id=s.user_id WHERE s.synthetic AND s.active ORDER BY student_code')).rows; });
    read('/simulator/events', simRoles, async ({ db, a }) => { requirePermission(a, 'simulator.use'); return { rfid: (await db.query('SELECT id,device_id,event_id,context_id,source,response,created_at FROM device_events ORDER BY created_at DESC LIMIT 50')).rows, face: (await db.query('SELECT * FROM simulation_events ORDER BY created_at DESC LIMIT 50')).rows, contexts: (await db.query("SELECT * FROM device_contexts WHERE status='OPEN' AND expires_at>now() ORDER BY created_at DESC LIMIT 20")).rows, identities: (await db.query('SELECT id,student_id,context_id,source,expires_at,consumed_at FROM identity_assertions ORDER BY created_at DESC LIMIT 20')).rows }; });
    write('/simulator/face-events', simRoles, ({ db, a, req }) => devices.demoFace(db, a, req.body), 'post', true);
    write('/simulator/ocr-observations', parkingRoles, ({ db, a, req }) => devices.demoOcr(db, a, req.body));
    write('/simulator/attendance-events', lecturerRoles, ({ db, a, req }) => attendance.attendanceDemo(db, a, req.body), 'post', true);
    write('/simulator/gate-scenarios', parkingRoles, async ({ db, a, req }) => { requirePermission(a, 'simulator.use'); const b = fields(req.body, ['commandId', 'scenario', 'providerEventId']); return parking.gateEvent(db, a, uuid(b.commandId), str(b.scenario, 30), str(b.providerEventId, 128)); }, 'post', true);
    write('/simulator/mock-topup-scenarios', ['ADMIN'], async ({ db, a, req }) => { requirePermission(a, 'simulator.use'); const b = fields(req.body, ['topupId', 'scenario']); const topup = await one(db, 'SELECT * FROM topup_orders WHERE id=$1', [uuid(b.topupId)]); return wallet.callback(db, { callbackId: 'scenario:' + id(), topupId: topup.id, amountPoints: topup.amount_points, status: choice(b.scenario, ['SUCCEEDED', 'FAILED'] as const) }); });
}
function registerAdmin(read: Read, write: Write) {
    read('/admin/reports', ['ADMIN'], async ({ db }) => ({ revenue: (await db.query("SELECT (t.created_at AT TIME ZONE 'Asia/Ho_Chi_Minh')::date AS day,coalesce(o.type,t.type) AS service,sum(CASE WHEN t.type IN('REFUND','REVERSAL') THEN -t.amount_points ELSE t.amount_points END)::text AS net_points FROM wallet_transactions t LEFT JOIN wallet_transactions o ON o.id=t.original_transaction_id WHERE t.type IN('CANTEEN_PAYMENT','PARKING_PAYMENT','REFUND','REVERSAL') GROUP BY 1,2 ORDER BY 1 DESC LIMIT 100")).rows, parking: (await db.query('SELECT status,count(*)::integer AS count FROM parking_sessions GROUP BY status')).rows, attendance: (await db.query('SELECT status,count(*)::integer AS count FROM attendance_records GROUP BY status')).rows, outbox: (await db.query('SELECT count(*) FILTER(WHERE published_at IS NULL)::integer AS pending,count(*) FILTER(WHERE dead_letter_at IS NOT NULL)::integer AS dead_letter FROM outbox_events')).rows[0] }));
    read('/admin/rfid-cards', ['ADMIN'], async ({ db }) => (await db.query('SELECT c.id,c.student_id,c.status,c.expires_at,s.student_code FROM rfid_cards c JOIN students s ON s.id=c.student_id ORDER BY c.created_at DESC LIMIT 100')).rows);
    read('/admin/settings', ['ADMIN'], async ({ db }) => ({ settings: (await db.query('SELECT * FROM system_settings')).rows, conversion: (await db.query('SELECT * FROM point_conversion_policies WHERE active')).rows[0] }));
    write('/admin/settings/wallet-limits', ['ADMIN'], async ({ db, a, req }) => { const b = fields(req.body, ['transactionPoints', 'dailyPoints', 'expectedVersion', 'reason']); const setting = await one(db, "SELECT * FROM system_settings WHERE key='wallet_limits' FOR UPDATE"); expected(setting.version, b.expectedVersion); const transactionPoints = points(b.transactionPoints), dailyPoints = points(b.dailyPoints); if (BigInt(dailyPoints) < BigInt(transactionPoints))
        reject(422, 'INVALID_LIMITS', 'Hạn mức ngày phải lớn hơn hoặc bằng mỗi giao dịch.'); await db.query("UPDATE system_settings SET value=$1,version=version+1,updated_at=now() WHERE key='wallet_limits'", [{ transactionPoints, dailyPoints }]); await audit(db, a, 'WALLET_LIMITS_CHANGED', null, str(b.reason, 1000, 5)); return { updated: true }; }, 'put');
    write('/admin/settings/point-conversion', ['ADMIN'], async ({ db, a, req }) => { const b = fields(req.body, ['version', 'pointsPerVnd', 'reason']); await db.query("SELECT pg_advisory_xact_lock(hashtextextended('point-conversion',0))"); await db.query('UPDATE point_conversion_policies SET active=false WHERE active'); await db.query('INSERT INTO point_conversion_policies VALUES($1,$2,true)', [str(b.version, 50), integer(b.pointsPerVnd, 1, 10000)]); await audit(db, a, 'POINT_CONVERSION_CHANGED', null, str(b.reason, 1000, 5)); return { updated: true }; }, 'put');
    write('/admin/users/:id/roles', ['ADMIN'], async ({ db, a, req }) => { const b = fields(req.body, ['roles', 'reason']); if (!Array.isArray(b.roles) || b.roles.length === 0 || b.roles.length > 5)
        reject(400, 'INVALID_ROLES', 'Cần 1–5 vai trò.'); const roles = [...new Set((b.roles as unknown[]).map(r => choice(r, ['ADMIN', 'STUDENT', 'LECTURER', 'PARKING_STAFF', 'CANTEEN_STAFF'] as const)))]; const userId = uuid(req.params.id); await db.query("SELECT pg_advisory_xact_lock(hashtextextended('last-admin',0))"); await one(db, 'SELECT id FROM users WHERE id=$1 FOR UPDATE', [userId]); if (!roles.includes('ADMIN') && await optional(db, "SELECT 1 FROM user_roles WHERE user_id=$1 AND role='ADMIN'", [userId])) {
        const others = await one(db, "SELECT count(*)::integer AS count FROM users u JOIN user_roles r ON r.user_id=u.id WHERE r.role='ADMIN' AND u.status='ACTIVE' AND u.id<>$1", [userId]);
        if (others.count === 0)
            reject(409, 'LAST_ADMIN', 'Không được gỡ quyền quản trị cuối cùng.');
    } if (roles.includes('STUDENT') && !await optional(db, 'SELECT id FROM students WHERE user_id=$1', [userId]))
        reject(422, 'STUDENT_PROFILE_REQUIRED', 'Tài khoản chưa có hồ sơ sinh viên.'); if (roles.includes('LECTURER') && !await optional(db, 'SELECT id FROM lecturers WHERE user_id=$1', [userId]))
        reject(422, 'LECTURER_PROFILE_REQUIRED', 'Tài khoản chưa có hồ sơ giảng viên.'); await db.query('DELETE FROM user_roles WHERE user_id=$1', [userId]); for (const role of roles)
        await db.query('INSERT INTO user_roles VALUES($1,$2)', [userId, role]); await db.query('UPDATE auth_sessions SET revoked_at=now() WHERE user_id=$1', [userId]); await audit(db, a, 'USER_ROLES_CHANGED', userId, str(b.reason, 1000, 5)); return { roles }; }, 'put');
    read('/admin/users', ['ADMIN'], async ({ db }) => (await db.query('SELECT u.id,u.email,u.name,u.status,st.id AS student_id,st.student_code,l.id AS lecturer_id,(SELECT array_agg(role) FROM user_roles WHERE user_id=u.id) AS roles FROM users u LEFT JOIN students st ON st.user_id=u.id LEFT JOIN lecturers l ON l.user_id=u.id ORDER BY email LIMIT 100')).rows);
    write('/admin/users', ['ADMIN'], async ({ db, a, req }) => {
        const b = fields(req.body, ['email', 'name', 'password', 'role', 'code']);
        const email = str(b.email, 200).toLowerCase();
        if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email))
            reject(400, 'INVALID_EMAIL', 'Email không hợp lệ.');
        const password = str(b.password, 200, 12), role = choice(b.role, ['STUDENT', 'LECTURER', 'PARKING_STAFF', 'CANTEEN_STAFF'] as const), userId = id();
        await db.query('INSERT INTO users(id,email,name,password_hash) VALUES($1,$2,$3,$4)', [userId, email, str(b.name, 120), await passwordHash(password)]);
        await db.query('INSERT INTO user_roles VALUES($1,$2)', [userId, role]);
        if (role === 'STUDENT') {
            const studentId = id(), accountId = id();
            await db.query('INSERT INTO students(id,user_id,student_code) VALUES($1,$2,$3)', [studentId, userId, str(b.code, 50)]);
            await db.query("INSERT INTO ledger_accounts(id,kind) VALUES($1,'STUDENT')", [accountId]);
            await db.query('INSERT INTO wallets(id,student_id,account_id) VALUES($1,$2,$3)', [id(), studentId, accountId]);
        }
        if (role === 'LECTURER')
            await db.query('INSERT INTO lecturers VALUES($1,$2,$3)', [id(), userId, str(b.code, 50)]);
        await audit(db, a, 'USER_CREATED', userId);
        return { id: userId };
    });
    write('/admin/users/:id/status', ['ADMIN'], async ({ db, a, req }) => {
        const b = fields(req.body, ['status', 'reason']);
        const target = uuid(req.params.id), status = choice(b.status, ['ACTIVE', 'LOCKED', 'DISABLED'] as const);
        await db.query("SELECT pg_advisory_xact_lock(hashtextextended('last-admin',0))");
        if (status !== 'ACTIVE' && await optional(db, "SELECT 1 FROM user_roles WHERE user_id=$1 AND role='ADMIN'", [target])) {
            const count = await one(db, "SELECT count(*)::integer AS count FROM users u JOIN user_roles r ON r.user_id=u.id WHERE r.role='ADMIN' AND u.status='ACTIVE'");
            if (count.count <= 1)
                reject(409, 'LAST_ADMIN', 'Không được khóa quản trị viên cuối cùng.');
        }
        await one(db, 'UPDATE users SET status=$2 WHERE id=$1 RETURNING id', [target, status]);
        if (status !== 'ACTIVE')
            await db.query('UPDATE auth_sessions SET revoked_at=now() WHERE user_id=$1', [target]);
        await audit(db, a, 'USER_STATUS_CHANGED', target, str(b.reason, 1000, 5));
        return { id: target, status };
    });
    read('/admin/roles', ['ADMIN'], async ({ db }) => ({ roles: (await db.query('SELECT * FROM roles')).rows, permissions: (await db.query('SELECT * FROM role_permissions')).rows }));
    read('/admin/devices', ['ADMIN'], async ({ db }) => (await db.query('SELECT id,name,kind,role,active,config_version,ack_version,last_seen_at,last_uid_mask,parking_lot_id,classroom_id FROM devices ORDER BY name')).rows);
    write('/admin/devices/:id/status', ['ADMIN'], async ({ db, a, req }) => { requirePermission(a, 'device.configure'); const b = fields(req.body, ['active', 'reason']); const active = bool(b.active), deviceId = uuid(req.params.id); await one(db, 'UPDATE devices SET active=$2 WHERE id=$1 RETURNING id', [deviceId, active]); if (!active)
        await db.query("UPDATE device_contexts SET status='CANCELLED' WHERE device_id=$1 AND status='OPEN'", [deviceId]); await audit(db, a, 'DEVICE_STATUS_CHANGED', deviceId, str(b.reason, 1000, 5)); return { active }; });
    write('/admin/devices/:id/role', ['ADMIN'], ({ db, a, req }) => devices.changeRole(db, a, uuid(req.params.id), req.body), 'put');
    write('/admin/devices', ['ADMIN'], async ({ db, a, req }) => { requirePermission(a, 'device.configure'); const b = fields(req.body, ['name', 'parkingLotId']); const deviceId = id(), secret = token(); await db.query("INSERT INTO devices(id,name,kind,token_hash,role,parking_lot_id) VALUES($1,$2,'RFID_READER',$3,'RFID_ENROLLMENT',$4)", [deviceId, str(b.name, 120), hash(secret), uuid(b.parkingLotId)]); await db.query("INSERT INTO device_role_bindings VALUES($1,$2,'RFID_ENROLLMENT',1,now(),NULL)", [id(), deviceId]); await audit(db, a, 'DEVICE_CREATED', deviceId); return { deviceId, deviceCredential: secret, displayOnce: true }; });
    write('/admin/devices/:id/rotate-credential', ['ADMIN'], async ({ db, a, req }) => { requirePermission(a, 'device.configure'); const b = fields(req.body, ['reason']); const secret = token(), deviceId = uuid(req.params.id); await one(db, 'UPDATE devices SET token_hash=$2 WHERE id=$1 RETURNING id', [deviceId, hash(secret)]); await audit(db, a, 'DEVICE_CREDENTIAL_ROTATED', deviceId, str(b.reason, 1000, 5)); return { deviceId, deviceCredential: secret, displayOnce: true }; });
    read('/admin/audit-logs', ['ADMIN'], async ({ db, a }) => { requirePermission(a, 'audit.read'); return (await db.query('SELECT * FROM audit_logs ORDER BY created_at DESC LIMIT 100')).rows; });
    read('/admin/vehicles', ['ADMIN'], async ({ db }) => (await db.query('SELECT v.*,a.student_id,a.active AS authorized FROM vehicles v JOIN vehicle_authorizations a ON a.vehicle_id=v.id ORDER BY v.normalized_plate LIMIT 100')).rows);
    read('/admin/parking-fee-policies', ['ADMIN'], async ({ db }) => (await db.query('SELECT * FROM parking_fee_policies ORDER BY created_at DESC')).rows);
    write('/admin/parking-fee-policies', ['ADMIN'], async ({ db, a, req }) => {
        const b = fields(req.body, ['lotId', 'version', 'mode', 'unitPoints', 'graceMinutes', 'dailyCap'], ['lotId', 'version', 'mode', 'unitPoints', 'graceMinutes']);
        const policyId = id();
        const unit = str(b.unitPoints, 10);
        if (!/^\d{1,9}$/.test(unit))
            reject(400, 'INVALID_AMOUNT', 'Phí không hợp lệ.');
        await db.query('INSERT INTO parking_fee_policies(id,lot_id,version,mode,unit_points,grace_minutes,daily_cap) VALUES($1,$2,$3,$4,$5,$6,$7)', [policyId, uuid(b.lotId), str(b.version, 50), choice(b.mode, ['PER_VISIT', 'PER_HOUR', 'PER_DAY'] as const), unit, integer(b.graceMinutes, 0, 1440), b.dailyCap ? points(b.dailyCap) : null]);
        await audit(db, a, 'PARKING_POLICY_CREATED', policyId);
        return { id: policyId };
    });
    write('/admin/parking-fee-policies/:id/activate', ['ADMIN'], async ({ db, a, req }) => { const policy = await one(db, 'SELECT * FROM parking_fee_policies WHERE id=$1', [uuid(req.params.id)]); await one(db, 'SELECT id FROM parking_lots WHERE id=$1 FOR UPDATE', [policy.lot_id]); await db.query('UPDATE parking_fee_policies SET active=false WHERE lot_id=$1 AND active', [policy.lot_id]); await db.query('UPDATE parking_fee_policies SET active=true WHERE id=$1', [policy.id]); await audit(db, a, 'PARKING_POLICY_ACTIVATED', policy.id); return { active: true }; });
    write('/admin/parking-passes', ['ADMIN'], async ({ db, a, req }) => { const b = fields(req.body, ['studentId', 'vehicleId', 'lotId', 'validFrom', 'validTo', 'reason', 'discountBps'], ['studentId', 'vehicleId', 'lotId', 'validFrom', 'validTo', 'reason']); const passId = id(); await db.query('INSERT INTO parking_passes(id,student_id,vehicle_id,lot_id,valid_from,valid_to,reason,discount_bps) VALUES($1,$2,$3,$4,$5,$6,$7,$8)', [passId, uuid(b.studentId), uuid(b.vehicleId), uuid(b.lotId), str(b.validFrom, 40), str(b.validTo, 40), str(b.reason, 1000, 5), b.discountBps === undefined ? 10000 : integer(b.discountBps, 0, 10000)]); await audit(db, a, 'PARKING_PASS_GRANTED', passId); return { id: passId }; });
    read('/admin/academic-terms', ['ADMIN'], async ({ db }) => (await db.query('SELECT * FROM academic_terms')).rows);
    read('/admin/courses', ['ADMIN'], async ({ db }) => (await db.query('SELECT * FROM courses')).rows);
    read('/admin/classrooms', lecturerRoles, async ({ db }) => (await db.query('SELECT * FROM classrooms')).rows);
    read('/admin/class-sections', ['ADMIN'], async ({ db }) => (await db.query('SELECT * FROM class_sections')).rows);
    read('/admin/schedules', ['ADMIN'], async ({ db }) => (await db.query('SELECT * FROM schedules ORDER BY starts_at DESC LIMIT 100')).rows);
    write('/admin/academic-terms', ['ADMIN'], async ({ db, a, req }) => { const b = fields(req.body, ['code', 'startsAt', 'endsAt']); const termId = id(); await db.query('INSERT INTO academic_terms VALUES($1,$2,$3,$4)', [termId, str(b.code, 50), str(b.startsAt, 40), str(b.endsAt, 40)]); await audit(db, a, 'ACADEMIC_TERM_CREATED', termId); return { id: termId }; });
    write('/admin/courses', ['ADMIN'], async ({ db, req }) => { const b = fields(req.body, ['code', 'name']); const courseId = id(); await db.query('INSERT INTO courses VALUES($1,$2,$3)', [courseId, str(b.code, 50), str(b.name, 200)]); return { id: courseId }; });
    write('/admin/classrooms', ['ADMIN'], async ({ db, req }) => { const b = fields(req.body, ['code', 'name']); const roomId = id(); await db.query('INSERT INTO classrooms VALUES($1,$2,$3)', [roomId, str(b.code, 50), str(b.name, 200)]); return { id: roomId }; });
    write('/admin/class-sections', ['ADMIN'], async ({ db, req }) => { const b = fields(req.body, ['termId', 'courseId', 'code']); const sectionId = id(); await db.query('INSERT INTO class_sections VALUES($1,$2,$3,$4)', [sectionId, uuid(b.termId), uuid(b.courseId), str(b.code, 50)]); return { id: sectionId }; });
    write('/admin/schedules', ['ADMIN'], async ({ db, req }) => { const b = fields(req.body, ['sectionId', 'classroomId', 'startsAt', 'endsAt']); const scheduleId = id(); await db.query('INSERT INTO schedules VALUES($1,$2,$3,$4,$5)', [scheduleId, uuid(b.sectionId), uuid(b.classroomId), str(b.startsAt, 40), str(b.endsAt, 40)]); return { id: scheduleId }; });
    write('/admin/class-sections/:id/enrollments', ['ADMIN'], async ({ db, req }) => { const b = fields(req.body, ['studentId']); await db.query('INSERT INTO enrollments VALUES($1,$2) ON CONFLICT DO NOTHING', [uuid(req.params.id), uuid(b.studentId)]); return { enrolled: true }; });
    write('/admin/class-sections/:id/teaching-assignments', ['ADMIN'], async ({ db, req }) => { const b = fields(req.body, ['lecturerId']); await db.query('INSERT INTO teaching_assignments VALUES($1,$2) ON CONFLICT DO NOTHING', [uuid(req.params.id), uuid(b.lecturerId)]); return { assigned: true }; });
}
