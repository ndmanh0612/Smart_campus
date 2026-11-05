import { audit, bool, choice, expected, fields, id, notify, one, optional, points, reject, requirePermission, str, uuid, type Actor, type Db, type Result } from './platform.ts';
import { consumeIdentity } from './devices.ts';
import { normalizePlate } from './providers.ts';
import { authorize, capture, post, voidPayment } from './wallet.ts';
export function calculateFee(policy: {
    mode: string;
    unit_points: string;
    grace_minutes: number;
    daily_cap: string | null;
}, enteredAt: Date, now: Date) {
    const elapsed = Math.max(0, now.getTime() - enteredAt.getTime());
    if (elapsed <= policy.grace_minutes * 60000)
        return '0';
    const unit = BigInt(policy.unit_points);
    const duration = elapsed - policy.grace_minutes * 60000;
    let fee = policy.mode === 'PER_VISIT' ? unit : policy.mode === 'PER_HOUR' ? unit * BigInt(Math.ceil(duration / 3600000)) : unit * BigInt(Math.ceil(duration / 86400000));
    if (policy.daily_cap) {
        const cap = BigInt(policy.daily_cap) * BigInt(Math.max(1, Math.ceil(elapsed / 86400000)));
        if (fee > cap)
            fee = cap;
    }
    return fee.toString();
}
async function plateObservation(db: Db, observationId: string, contextId: string) {
    const observation = await one(db, 'SELECT * FROM ocr_observations WHERE id=$1 AND context_id=$2', [observationId, contextId]);
    const correction = await optional(db, 'SELECT * FROM ocr_corrections WHERE observation_id=$1 ORDER BY created_at DESC,id DESC LIMIT 1', [observation.id]);
    if (!correction && (observation.status !== 'READ' || Number(observation.confidence) < 0.8))
        reject(422, 'OCR_REVIEW_REQUIRED', 'OCR demo cần nhân viên xác minh và ghi lý do.');
    const normalized = correction?.corrected_plate ?? observation.normalized_plate;
    if (!normalized)
        reject(422, 'PLATE_UNREADABLE', 'Chưa có biển số hợp lệ.');
    return { observation, plate: normalized as string };
}
async function vehicleAllowed(db: Db, studentId: string, vehicleId: string) {
    if (!await optional(db, 'SELECT 1 FROM vehicle_authorizations a JOIN vehicles v ON v.id=a.vehicle_id WHERE a.vehicle_id=$1 AND a.student_id=$2 AND a.active AND v.active AND a.valid_from<=now() AND (a.valid_to IS NULL OR a.valid_to>now())', [vehicleId, studentId]))
        reject(422, 'VEHICLE_NOT_AUTHORIZED', 'Sinh viên không có quyền sử dụng xe này.');
}
async function command(db: Db, session: Record<string, any>, deviceId: string, phase: string) { const commandId = id(); await db.query("INSERT INTO gate_commands VALUES($1,$2,$3,$4,$5,'QUEUED',now()+interval '30 seconds',now())", [commandId, session.id, deviceId, phase, session.settlement_cycle]); return commandId; }
export async function entry(db: Db, a: Actor, body: unknown) {
    const b = fields(body, ['identityAssertionId', 'ocrObservationId']);
    const identity = await consumeIdentity(db, uuid(b.identityAssertionId), 'PARKING_ENTRY');
    const lotId = identity.parking_lot_id;
    const ocr = await plateObservation(db, uuid(b.ocrObservationId), identity.context_id);
    const vehicle = await one(db, 'SELECT * FROM vehicles WHERE normalized_plate=$1 AND active FOR UPDATE', [ocr.plate]);
    await vehicleAllowed(db, identity.student_id, vehicle.id);
    const lot = await one(db, 'SELECT * FROM parking_lots WHERE id=$1 FOR UPDATE', [lotId]);
    const occupancy = await one(db, 'SELECT count(*)::integer AS count FROM parking_occupancies WHERE lot_id=$1', [lotId]);
    if (occupancy.count >= lot.capacity)
        reject(422, 'PARKING_FULL', 'Bãi xe đã đủ chỗ.');
    const policy = await one(db, 'SELECT * FROM parking_fee_policies WHERE lot_id=$1 AND active', [lotId]);
    const sessionId = id();
    await db.query("INSERT INTO parking_sessions(id,student_id,vehicle_id,lot_id,policy_id,status,entry_plate,entry_source) VALUES($1,$2,$3,$4,$5,'PENDING_ENTRY',$6,$7)", [sessionId, identity.student_id, vehicle.id, lotId, policy.id, ocr.plate, identity.source]);
    await db.query('INSERT INTO parking_occupancies VALUES($1,$2,$3)', [vehicle.id, sessionId, lotId]);
    const commandId = await command(db, { id: sessionId, settlement_cycle: 1 }, identity.device_id, 'ENTRY');
    await db.query('UPDATE identity_assertions SET resource_id=$2 WHERE id=$1', [identity.id, sessionId]);
    await db.query("INSERT INTO parking_events(id,session_id,type,actor_id,source,evidence_ref) VALUES($1,$2,'ENTRY_REQUESTED',$3,$4,$5)", [id(), sessionId, a.id, identity.source, ocr.observation.id]);
    await audit(db, a, 'PARKING_ENTRY_REQUESTED', sessionId);
    return { id: sessionId, status: 'PENDING_ENTRY', commandId, source: identity.source, plate: ocr.plate };
}
export async function exitQuote(db: Db, a: Actor, sessionId: string, body: unknown) {
    const b = fields(body, ['identityAssertionId', 'ocrObservationId', 'expectedVersion']);
    const session = await one(db, 'SELECT * FROM parking_sessions WHERE id=$1 FOR UPDATE', [sessionId]);
    expected(session.version, b.expectedVersion);
    if (session.status !== 'ACTIVE')
        reject(409, 'PARKING_STATE', 'Phiên không ở trạng thái đang gửi xe.');
    const identity = await consumeIdentity(db, uuid(b.identityAssertionId), 'PARKING_EXIT', sessionId);
    if (identity.student_id !== session.student_id)
        reject(403, 'PARKING_OWNER_MISMATCH', 'Sinh viên không phải người đứng tên lượt gửi xe.');
    const ocr = await plateObservation(db, uuid(b.ocrObservationId), identity.context_id);
    if (ocr.plate !== session.entry_plate)
        reject(422, 'PLATE_MISMATCH', 'Biển số ra không khớp biển số vào.');
    await vehicleAllowed(db, identity.student_id, session.vehicle_id);
    const policy = await one(db, 'SELECT * FROM parking_fee_policies WHERE id=$1', [session.policy_id]);
    const pass = await optional(db, 'SELECT id,discount_bps FROM parking_passes WHERE student_id=$1 AND vehicle_id=$2 AND lot_id=$3 AND valid_from<=now() AND valid_to>now() ORDER BY discount_bps DESC,id LIMIT 1', [session.student_id, session.vehicle_id, session.lot_id]);
    const baseFee = calculateFee(policy, new Date(session.entered_at), new Date());
    const amount = pass ? ((BigInt(baseFee) * BigInt(10000 - pass.discount_bps) + 9999n) / 10000n).toString() : baseFee;
    const prior = (await db.query("SELECT id FROM payments WHERE parking_session_id=$1 AND settlement_cycle=$2 AND status='AWAITING_CONFIRMATION' FOR UPDATE", [sessionId, session.settlement_cycle])).rows;
    for (const p of prior)
        await voidPayment(db, p.id);
    const quoteId = id();
    await db.query("INSERT INTO parking_quotes(id,session_id,settlement_cycle,amount_points,fee_snapshot,expires_at) VALUES($1,$2,$3,$4,$5,now()+interval '120 seconds')", [quoteId, sessionId, session.settlement_cycle, amount, { policyId: policy.id, policyVersion: policy.version, mode: policy.mode, passId: pass?.id ?? null, dayDefinition: 'BLOCK_24_HOURS', source: 'SERVER' }]);
    let paymentId: string | null = null;
    if (amount !== '0') {
        paymentId = id();
        await db.query("INSERT INTO payments(id,student_id,parking_session_id,quote_id,settlement_cycle,amount_points,status,identity_assertion_id) VALUES($1,$2,$3,$4,$5,$6,'AWAITING_CONFIRMATION',$7)", [paymentId, session.student_id, sessionId, quoteId, session.settlement_cycle, amount, identity.id]);
        await db.query('INSERT INTO parking_payments VALUES($1,$2,$3)', [paymentId, sessionId, quoteId]);
        await notify(db, session.student_id, 'payment.changed', `Phí gửi xe cần xác nhận ${amount} point.`, paymentId);
    }
    await db.query('UPDATE parking_sessions SET exit_plate=$2 WHERE id=$1', [sessionId, ocr.plate]);
    await db.query("INSERT INTO parking_events(id,session_id,type,actor_id,source,evidence_ref,metadata) VALUES($1,$2,'EXIT_QUOTED',$3,$4,$5,$6)", [id(), sessionId, a.id, identity.source, ocr.observation.id, { quoteId, identityId: identity.id }]);
    return { quoteId, paymentId, amountPoints: amount, settlementCycle: session.settlement_cycle, sourceVersion: session.version, approvalRequired: amount !== '0', expiresIn: 120 };
}
export async function exitAuthorize(db: Db, a: Actor, sessionId: string, body: unknown) {
    const b = fields(body, ['quoteId', 'approvalId', 'expectedVersion'], ['quoteId', 'expectedVersion']);
    const session = await one(db, 'SELECT * FROM parking_sessions WHERE id=$1 FOR UPDATE', [sessionId]);
    expected(session.version, b.expectedVersion);
    if (session.status !== 'ACTIVE')
        reject(409, 'PARKING_STATE', 'Phiên không còn chờ lấy xe.');
    const quote = await one(db, 'SELECT * FROM parking_quotes WHERE id=$1 AND session_id=$2', [uuid(b.quoteId), sessionId]);
    if (quote.settlement_cycle !== session.settlement_cycle || new Date(quote.expires_at) < new Date())
        reject(422, 'QUOTE_EXPIRED', 'Báo giá đã hết hạn.');
    const event = await one(db, "SELECT a.device_id FROM parking_events e JOIN identity_assertions a ON a.id=(e.metadata->>'identityId')::uuid WHERE e.session_id=$1 AND e.type='EXIT_QUOTED' AND e.metadata->>'quoteId'=$2", [sessionId, quote.id]);
    if (quote.amount_points !== '0') {
        const p = await one(db, 'SELECT * FROM payments WHERE quote_id=$1 FOR UPDATE', [quote.id]);
        await authorize(db, p, session.version, uuid(b.approvalId));
    }
    const commandId = await command(db, session, event.device_id, 'EXIT');
    await db.query("UPDATE parking_sessions SET status='EXIT_PENDING',version=version+1 WHERE id=$1", [sessionId]);
    await audit(db, a, 'PARKING_EXIT_AUTHORIZED', sessionId);
    return { id: sessionId, status: 'EXIT_PENDING', commandId, amountPoints: quote.amount_points };
}
export async function gateEvent(db: Db, a: Actor | null, commandId: string, scenario: string, providerEventId: string): Promise<Result> {
    choice(scenario, ['OPENED', 'FAIL_BEFORE_OPEN', 'TIMEOUT_UNKNOWN', 'PASSAGE', 'LATE_ACK'] as const);
    const ref = await one(db, 'SELECT session_id FROM gate_commands WHERE id=$1', [commandId]);
    const session = await one(db, 'SELECT * FROM parking_sessions WHERE id=$1 FOR UPDATE', [ref.session_id]);
    const cmd = await one(db, 'SELECT * FROM gate_commands WHERE id=$1 FOR UPDATE', [commandId]);
    const prior = await optional(db, 'SELECT * FROM gate_provider_events WHERE provider_event_id=$1', [providerEventId]);
    if (prior) {
        if (prior.command_id !== commandId || prior.type !== scenario)
            reject(409, 'GATE_EVENT_CONFLICT', 'Sự kiện cổng bị thay đổi.');
        return { data: { commandId, status: cmd.status, sessionStatus: session.status, source: 'SIMULATOR' } };
    }
    await db.query("INSERT INTO gate_provider_events VALUES($1,$2,$3,$4,'SIMULATOR',now())", [id(), commandId, providerEventId, scenario]);
    if (cmd.status === 'REVOKED' || cmd.settlement_cycle !== session.settlement_cycle || scenario === 'LATE_ACK') {
        await audit(db, a, 'LATE_GATE_EVENT', session.id, undefined, { commandId, scenario });
        return { status: 409, error: { code: 'GATE_COMMAND_FENCED', message: 'Lệnh cổng cũ đã vô hiệu; cần đối soát, không tự thu lại.' } };
    }
    if (cmd.status === 'PASSAGE_CONFIRMED')
        return { data: { commandId, status: cmd.status, sessionStatus: session.status, source: 'SIMULATOR' } };
    if (scenario === 'OPENED') {
        if (!['QUEUED', 'DISPATCHED'].includes(cmd.status) || new Date(cmd.expires_at) < new Date())
            reject(409, 'GATE_STATE', 'Lệnh không còn được mở cổng.');
        await db.query("UPDATE gate_commands SET status='OPENED' WHERE id=$1", [commandId]);
    }
    else if (scenario === 'TIMEOUT_UNKNOWN') {
        if (!['QUEUED', 'DISPATCHED', 'OPENED'].includes(cmd.status))
            reject(409, 'GATE_STATE', 'Trạng thái cổng không phù hợp.');
        await db.query("UPDATE gate_commands SET status='UNKNOWN' WHERE id=$1", [commandId]);
        await db.query("UPDATE parking_sessions SET status='EXCEPTION',version=version+1 WHERE id=$1", [session.id]);
    }
    else if (scenario === 'FAIL_BEFORE_OPEN') {
        if (!['QUEUED', 'DISPATCHED'].includes(cmd.status))
            reject(409, 'GATE_STATE', 'Không thể khẳng định chưa mở sau khi có ACK mở.');
        await db.query("UPDATE gate_commands SET status='FAILED' WHERE id=$1", [commandId]);
        if (cmd.phase === 'ENTRY') {
            await db.query("UPDATE parking_sessions SET status='CANCELLED',version=version+1 WHERE id=$1", [session.id]);
            await db.query('DELETE FROM parking_occupancies WHERE session_id=$1', [session.id]);
        }
        else {
            const p = await optional(db, "SELECT id FROM payments WHERE parking_session_id=$1 AND settlement_cycle=$2 AND status='AUTHORIZED' FOR UPDATE", [session.id, session.settlement_cycle]);
            if (p)
                await voidPayment(db, p.id);
            await db.query("UPDATE parking_sessions SET status='ACTIVE',version=version+1 WHERE id=$1", [session.id]);
        }
    }
    else if (scenario === 'PASSAGE') {
        if (!['OPENED', 'UNKNOWN'].includes(cmd.status))
            reject(409, 'GATE_NOT_OPENED', 'Phải có ACK mở hoặc xác minh cổng UNKNOWN trước khi xác nhận xe qua.');
        if (cmd.phase === 'ENTRY')
            await db.query("UPDATE parking_sessions SET status='ACTIVE',entered_at=clock_timestamp(),version=version+1 WHERE id=$1 AND status IN('PENDING_ENTRY','EXCEPTION')", [session.id]);
        else {
            if (!['EXIT_PENDING', 'EXCEPTION'].includes(session.status))
                reject(409, 'PARKING_STATE', 'Phiên không còn chờ xác nhận ra.');
            const p = await optional(db, "SELECT * FROM payments WHERE parking_session_id=$1 AND settlement_cycle=$2 AND status='AUTHORIZED' FOR UPDATE", [session.id, session.settlement_cycle]);
            if (p)
                await capture(db, p);
            else {
                const q = await one(db, 'SELECT amount_points FROM parking_quotes WHERE session_id=$1 AND settlement_cycle=$2 ORDER BY created_at DESC LIMIT 1', [session.id, session.settlement_cycle]);
                if (q.amount_points !== '0')
                    reject(409, 'PAYMENT_STATE', 'Thiếu phần point được giữ cho lượt ra.');
            }
            await db.query("UPDATE parking_sessions SET status='COMPLETED',exited_at=clock_timestamp(),version=version+1 WHERE id=$1", [session.id]);
            await db.query('DELETE FROM parking_occupancies WHERE session_id=$1', [session.id]);
        }
        await db.query("UPDATE gate_commands SET status='PASSAGE_CONFIRMED' WHERE id=$1", [commandId]);
        await notify(db, session.student_id, 'parking.session.changed', cmd.phase === 'ENTRY' ? 'Đã xác nhận xe vào bãi mô phỏng.' : 'Đã xác nhận xe ra bãi và quyết toán point.', session.id);
    }
    await audit(db, a, 'GATE_SIMULATOR_' + scenario, session.id, undefined, { commandId, source: 'SIMULATOR' });
    const current = await one(db, 'SELECT status FROM gate_commands WHERE id=$1', [commandId]);
    const updated = await one(db, 'SELECT status FROM parking_sessions WHERE id=$1', [session.id]);
    return { data: { commandId, status: current.status, sessionStatus: updated.status, source: 'SIMULATOR' } };
}
export async function resolveException(db: Db, a: Actor, sessionId: string, body: unknown) {
    requirePermission(a, 'parking.exception.resolve');
    const b = fields(body, ['resolution', 'reason', 'evidenceNote', 'expectedVersion']);
    const resolution = choice(b.resolution, ['VEHICLE_STILL_INSIDE', 'CANCEL_ENTRY', 'REVERSE_CAPTURE'] as const), reason = str(b.reason, 1000, 5), evidenceNote = str(b.evidenceNote, 1000, 5);
    const session = await one(db, 'SELECT * FROM parking_sessions WHERE id=$1 FOR UPDATE', [sessionId]);
    expected(session.version, b.expectedVersion);
    if (resolution === 'REVERSE_CAPTURE') {
        if (session.status !== 'COMPLETED')
            reject(409, 'PARKING_STATE', 'Chỉ đối soát khoản đã thu của phiên hoàn tất.');
        const p = await one(db, "SELECT * FROM payments WHERE parking_session_id=$1 AND settlement_cycle=$2 AND status='CAPTURED' FOR UPDATE", [sessionId, session.settlement_cycle]);
        const original = await one(db, 'SELECT * FROM wallet_transactions WHERE payment_id=$1', [p.id]);
        await db.query('SELECT pg_advisory_xact_lock(hashtextextended($1,0))', ['refund:' + original.id]);
        if (await optional(db, 'SELECT id FROM refunds WHERE original_transaction_id=$1', [original.id]))
            reject(409, 'ALREADY_REFUNDED', 'Giao dịch đã có hoàn tiền.');
        const refundId = id();
        await db.query('INSERT INTO refunds(id,original_transaction_id,amount_points,reason,actor_id) VALUES($1,$2,$3,$4,$5)', [refundId, original.id, original.amount_points, reason, a.id]);
        await post(db, 'REVERSAL', session.student_id, original.amount_points, { original: original.id, refund: refundId });
        await db.query('INSERT INTO parking_occupancies VALUES($1,$2,$3)', [session.vehicle_id, session.id, session.lot_id]);
        await db.query("UPDATE parking_sessions SET status='ACTIVE',settlement_cycle=settlement_cycle+1,exited_at=NULL,version=version+1 WHERE id=$1", [sessionId]);
    }
    else {
        if (!['EXCEPTION', 'EXIT_PENDING', 'PENDING_ENTRY'].includes(session.status))
            reject(409, 'PARKING_STATE', 'Phiên không có ngoại lệ phù hợp.');
        const cmd = await one(db, 'SELECT * FROM gate_commands WHERE session_id=$1 AND status IN(\'QUEUED\',\'DISPATCHED\',\'OPENED\',\'UNKNOWN\') ORDER BY created_at DESC LIMIT 1 FOR UPDATE', [sessionId]);
        if (resolution === 'CANCEL_ENTRY' && cmd.phase !== 'ENTRY' || resolution === 'VEHICLE_STILL_INSIDE' && cmd.phase !== 'EXIT')
            reject(409, 'EXCEPTION_PHASE', 'Cách xử lý không khớp pha vào/ra.');
        const p = await optional(db, "SELECT id FROM payments WHERE parking_session_id=$1 AND settlement_cycle=$2 AND status IN('AUTHORIZED','AWAITING_CONFIRMATION') FOR UPDATE", [sessionId, session.settlement_cycle]);
        if (p)
            await voidPayment(db, p.id);
        await db.query('UPDATE parking_sessions SET status=$2,version=version+1 WHERE id=$1', [sessionId, resolution === 'CANCEL_ENTRY' ? 'CANCELLED' : 'ACTIVE']);
        if (resolution === 'CANCEL_ENTRY')
            await db.query('DELETE FROM parking_occupancies WHERE session_id=$1', [sessionId]);
    }
    await db.query("UPDATE gate_commands SET status='REVOKED' WHERE session_id=$1 AND status<>'FAILED'", [sessionId]);
    await db.query("INSERT INTO parking_events(id,session_id,type,actor_id,source,metadata) VALUES($1,$2,'EXCEPTION_RESOLVED',$3,'MANUAL',$4)", [id(), sessionId, a.id, { resolution, reason, evidenceNote, vehicleInside: resolution !== 'CANCEL_ENTRY' }]);
    await audit(db, a, 'PARKING_EXCEPTION_RESOLVED', sessionId, reason, { resolution, evidenceNote });
    return one(db, 'SELECT * FROM parking_sessions WHERE id=$1', [sessionId]);
}
