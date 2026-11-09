import { ApiError, audit, choice, expected, fields, hash, id, integer, one, optional, reject, requirePermission, str, uidHash, uuid, type Actor, type CampusConfig, type Db, type Result } from './platform.ts';
import { DemoCameraProvider, DemoFaceProvider, DemoOCRProvider } from './providers.ts';
const roleForPurpose: Record<string, string> = { PARKING_ENTRY: 'PARKING_ENTRY', PARKING_EXIT: 'PARKING_EXIT', CANTEEN: 'CANTEEN_POS', ENROLLMENT: 'RFID_ENROLLMENT', ATTENDANCE: 'ATTENDANCE_CAMERA' };
export async function deviceAuth(db: Db, header: string) {
    if (!/^Bearer [\w-]{40,100}$/.test(header))
        reject(401, 'DEVICE_UNAUTHORIZED', 'Thiếu xác thực thiết bị.');
    return (await optional(db, "SELECT * FROM devices WHERE token_hash=$1 AND active AND kind='RFID_READER'", [hash(header.slice(7))])) ?? reject(401, 'DEVICE_UNAUTHORIZED', 'Thiết bị không hợp lệ.');
}
export async function createContext(db: Db, deviceId: string, purpose: string, targetId: string) {
    const device = await one(db, 'SELECT * FROM devices WHERE id=$1 AND active FOR UPDATE', [deviceId]);
    if (device.role !== roleForPurpose[purpose] || device.config_version !== device.ack_version)
        reject(409, 'DEVICE_ROLE_MISMATCH', 'Thiết bị chưa xác nhận đúng vai trò.');
    await db.query("UPDATE device_contexts SET status='CANCELLED' WHERE device_id=$1 AND status='OPEN'", [deviceId]);
    const contextId = id();
    const columns: Record<string, string> = { PARKING_ENTRY: 'parking_lot_id', PARKING_EXIT: 'parking_session_id', CANTEEN: 'order_id', ENROLLMENT: 'enrollment_student_id', ATTENDANCE: 'attendance_session_id' };
    const column = columns[purpose];
    if (!column)
        reject(400, 'INVALID_PURPOSE', 'Mục đích không hợp lệ.');
    await db.query(`INSERT INTO device_contexts(id,device_id,purpose,${column},config_version,expires_at) VALUES($1,$2,$3,$4,$5,now()+interval '5 minutes')`, [contextId, deviceId, purpose, targetId, device.config_version]);
    return { id: contextId, deviceId, purpose, configVersion: device.config_version };
}
export async function changeRole(db: Db, a: Actor, deviceId: string, body: unknown) {
    requirePermission(a, 'device.configure');
    const b = fields(body, ['role', 'expectedVersion', 'reason']);
    const role = choice(b.role, ['PARKING_ENTRY', 'PARKING_EXIT', 'CANTEEN_POS', 'RFID_ENROLLMENT'] as const), reason = str(b.reason, 1000, 5);
    const device = await one(db, "SELECT * FROM devices WHERE id=$1 AND kind='RFID_READER' FOR UPDATE", [deviceId]);
    expected(device.config_version, b.expectedVersion);
    await db.query("UPDATE device_contexts SET status='CANCELLED' WHERE device_id=$1 AND status='OPEN'", [deviceId]);
    const busy = await optional(db, `SELECT 1 FROM device_contexts WHERE device_id=$1 AND status='OPEN'
    UNION ALL SELECT 1 FROM gate_commands WHERE device_id=$1 AND status IN('QUEUED','DISPATCHED','OPENED','UNKNOWN')
    UNION ALL SELECT 1 FROM payments p JOIN identity_assertions a ON a.id=p.identity_assertion_id WHERE a.device_id=$1 AND p.status IN('AWAITING_CONFIRMATION','AUTHORIZED') LIMIT 1`, [deviceId]);
    if (busy)
        reject(409, 'DEVICE_BUSY', 'Thiết bị còn thao tác chờ xử lý; hãy hoàn tất hoặc hủy trước.');
    await db.query('UPDATE device_role_bindings SET released_at=now() WHERE device_id=$1 AND released_at IS NULL', [deviceId]);
    const d = await one(db, 'UPDATE devices SET role=$2,config_version=config_version+1 WHERE id=$1 RETURNING *', [deviceId, role]);
    await db.query('INSERT INTO device_role_bindings VALUES($1,$2,$3,$4,now(),NULL)', [id(), deviceId, role, d.config_version]);
    await audit(db, a, 'DEVICE_ROLE_CHANGED', deviceId, reason, { role, configVersion: d.config_version });
    return { deviceId, role, configVersion: d.config_version, acknowledged: false };
}
export async function deviceConfig(db: Db, d: Record<string, any>) {
    await db.query('UPDATE devices SET last_seen_at=now() WHERE id=$1', [d.id]);
    const context = await optional(db, "SELECT id,purpose,expires_at FROM device_contexts WHERE device_id=$1 AND status='OPEN' AND expires_at>now()", [d.id]);
    return { deviceId: d.id, role: d.role, configVersion: d.config_version, acknowledged: d.ack_version === d.config_version, context: context ?? null, serverTime: new Date().toISOString() };
}
export async function challenge(db: Db, d: Record<string, any>, body: unknown) {
    const b = fields(body, ['deviceId', 'configVersion', 'contextId']);
    if (uuid(b.deviceId) !== d.id || integer(b.configVersion) !== d.config_version || d.ack_version !== d.config_version)
        reject(409, 'DEVICE_ROLE_MISMATCH', 'Sai thiết bị hoặc cấu hình chưa xác nhận.');
    const ctx = await one(db, "SELECT * FROM device_contexts WHERE id=$1 AND device_id=$2 AND status='OPEN' AND expires_at>now()", [uuid(b.contextId), d.id]);
    const nonce = id() + id(), challengeId = id();
    await db.query("INSERT INTO device_challenges VALUES($1,$2,$3,$4,$5,now()+interval '60 seconds',NULL)", [challengeId, d.id, ctx.id, hash(nonce), d.config_version]);
    return { challengeId, nonce, expiresIn: 60, serverTime: new Date().toISOString() };
}
export async function scan(db: Db, d: Record<string, any>, body: unknown, cfg: CampusConfig): Promise<Result> {
    const b = fields(body, ['schemaVersion', 'eventId', 'deviceId', 'deviceRole', 'configVersion', 'contextId', 'challengeId', 'nonce', 'occurredAt', 'credential']);
    const eventId = uuid(b.eventId);
    const credential = fields(b.credential, ['type', 'uid']);
    if (integer(b.schemaVersion) !== 1 || credential.type !== 'RFID_UID')
        reject(400, 'INVALID_EVENT', 'Schema hoặc loại credential không hợp lệ.');
    if (uuid(b.deviceId) !== d.id || b.deviceRole !== d.role || integer(b.configVersion) !== d.config_version || d.ack_version !== d.config_version)
        reject(409, 'DEVICE_ROLE_MISMATCH', 'Thiết bị chưa đúng vai trò/cấu hình.');
    const uid = str(credential.uid, 20).toUpperCase();
    if (!/^(?:[0-9A-F]{8}|[0-9A-F]{14}|[0-9A-F]{20})$/.test(uid))
        reject(400, 'INVALID_UID', 'UID phải đủ hai ký tự hex mỗi byte.');
    const occurredAt = Date.parse(str(b.occurredAt, 40));
    if (!Number.isFinite(occurredAt) || Math.abs(Date.now() - occurredAt) > 120000)
        reject(422, 'STALE_EVENT', 'Sự kiện quá hạn hoặc đồng hồ chưa đồng bộ.');
    const context = await one(db, "SELECT * FROM device_contexts WHERE id=$1 AND device_id=$2 AND status='OPEN' AND expires_at>now() FOR UPDATE", [uuid(b.contextId), d.id]);
    const c = await one(db, 'SELECT * FROM device_challenges WHERE id=$1 AND device_id=$2 AND context_id=$3 FOR UPDATE', [uuid(b.challengeId), d.id, context.id]);
    if (c.consumed_at || new Date(c.expires_at) < new Date() || c.nonce_hash !== hash(str(b.nonce, 200)) || c.config_version !== d.config_version)
        reject(422, 'REPLAY_DETECTED', 'Challenge không hợp lệ, hết hạn hoặc đã dùng.');
    await db.query('UPDATE device_challenges SET consumed_at=now() WHERE id=$1', [c.id]);
    await db.query('UPDATE devices SET last_seen_at=now(),last_uid_mask=$2 WHERE id=$1', [d.id, '****' + uid.slice(-4)]);
    let result: Result;
    const digest = uidHash(uid, cfg.cardKey);
    const card = await optional(db, "SELECT c.*,s.active,u.status AS user_status FROM rfid_cards c JOIN students s ON s.id=c.student_id JOIN users u ON u.id=s.user_id WHERE c.uid_hmac=$1 AND c.status='ACTIVE' AND (c.expires_at IS NULL OR c.expires_at>now())", [digest]);
    if (context.purpose === 'ENROLLMENT') {
        if (card && card.student_id !== context.enrollment_student_id)
            result = { status: 422, error: { code: 'CARD_ALREADY_ASSIGNED', message: 'Thẻ đang thuộc sinh viên khác.' } };
        else
            result = await assertion(db, context, context.enrollment_student_id, 'REAL', card?.id ?? null, digest);
    }
    else if (!card || !card.active || card.user_status !== 'ACTIVE')
        result = { status: 422, error: { code: 'CARD_NOT_ACTIVE', message: 'Thẻ hoặc sinh viên không còn hiệu lực.' } };
    else
        result = await assertion(db, context, card.student_id, 'REAL', card.id, null);
    if (result.data)
        result.data = { ...result.data as object, eventId, actionId: context.id, actionStatus: 'AWAITING_CONFIRMATION' };
    const response = result.error ? { error: result.error } : { data: result.data };
    await db.query("INSERT INTO device_events(id,device_id,event_id,context_id,payload_hash,response,http_status,source) VALUES($1,$2,$3,$4,$5,$6,$7,'REAL')", [id(), d.id, eventId, context.id, hash(JSON.stringify(body)), response, result.status ?? 202]);
    return result;
}
export async function deviceAction(db: Db, d: Record<string, any>, contextId: string) {
    const c = await one(db, 'SELECT * FROM device_contexts WHERE id=$1 AND device_id=$2', [contextId, d.id]);
    const a = await optional(db, 'SELECT * FROM identity_assertions WHERE context_id=$1 ORDER BY created_at DESC LIMIT 1', [c.id]);
    let status = c.status, terminal = false, lcdLines = ['CHO XAC NHAN', 'XEM UNG DUNG'];
    if (c.order_id) {
        const o = await one(db, 'SELECT status FROM orders WHERE id=$1', [c.order_id]);
        status = o.status;
        terminal = ['COMPLETED', 'CANCELLED', 'EXPIRED'].includes(status);
        if (status === 'COMPLETED')
            lcdLines = ['DA THANH TOAN', 'CAM ON BAN'];
    }
    else if (c.parking_session_id || (c.purpose === 'PARKING_ENTRY' && a?.resource_id)) {
        const s = await one(db, 'SELECT status FROM parking_sessions WHERE id=$1', [c.parking_session_id ?? a.resource_id]);
        status = s.status;
        terminal = c.purpose === 'PARKING_ENTRY' ? ['ACTIVE', 'CANCELLED'].includes(status) : ['COMPLETED', 'CANCELLED'].includes(status);
        if (terminal)
            lcdLines = [status === 'ACTIVE' ? 'XE DA VAO' : 'XE DA RA', 'CONG MO PHONG'];
        if (status === 'EXCEPTION')
            lcdLines = ['CAN DOI SOAT', 'LIEN HE NHAN VIEN'];
    }
    else if (c.purpose === 'ENROLLMENT' && a?.resource_id) {
        status = 'CARD_ENROLLED';
        terminal = true;
        lcdLines = ['DA GAN THE', 'THANH CONG'];
    }
    if (a && !terminal) {
        const p = await optional(db, "SELECT p.amount_points,l.balance_points-coalesce((SELECT sum(h.amount_points) FROM wallet_holds h WHERE h.wallet_id=w.id AND h.status='ACTIVE'),0) AS available FROM payments p JOIN wallets w ON w.student_id=p.student_id JOIN ledger_accounts l ON l.id=w.account_id WHERE p.identity_assertion_id=$1 AND p.status='AWAITING_CONFIRMATION'", [a.id]);
        if (p && BigInt(p.available) < BigInt(p.amount_points)) {
            status = 'INSUFFICIENT_POINTS';
            lcdLines = ['KHONG DU POINT', 'THIEU ' + (BigInt(p.amount_points) - BigInt(p.available)).toString() + ' P'];
        }
    }
    if (c.status === 'OPEN' && a && !a.consumed_at && new Date(a.expires_at) < new Date()) {
        const cancelled = await db.query("UPDATE device_contexts SET status='CANCELLED' WHERE id=$1 AND status='OPEN' RETURNING id", [c.id]);
        if (cancelled.rowCount) {
            status = 'IDENTITY_EXPIRED';
            terminal = true;
            lcdLines = ['XAC THUC HET HAN', 'TAO PHIEN QUET LAI'];
        }
    }
    if (c.status === 'CANCELLED') {
        status = 'CANCELLED';
        terminal = true;
        lcdLines = ['DA HUY / HET HAN', 'QUET LAI KHI CAN'];
    }
    return { actionId: c.id, status, terminal, lcdLines, validUntil: new Date(Date.now() + 15000).toISOString() };
}
async function assertion(db: Db, context: Record<string, any>, studentId: string, source: 'REAL' | 'DEMO', cardId: string | null = null, digest: string | null = null): Promise<Result> {
    const assertionId = id();
    await db.query("INSERT INTO identity_assertions(id,student_id,device_id,context_id,source,card_id,credential_hmac,expires_at) VALUES($1,$2,$3,$4,$5,$6,$7,now()+interval '60 seconds')", [assertionId, studentId, context.device_id, context.id, source, cardId, digest]);
    return { status: 202, data: { identityAssertionId: assertionId, studentId, contextId: context.id, source, outcome: 'IDENTIFIED', lcdLines: ['THE HOP LE', 'CHO XAC NHAN'], validUntil: new Date(Date.now() + 60000).toISOString() } };
}
export async function consumeIdentity(db: Db, assertionId: string, purpose: string, targetId?: string) {
    const identity = await one(db, 'SELECT a.*,c.purpose,c.status AS context_status,c.order_id,c.parking_session_id,c.parking_lot_id,c.enrollment_student_id,c.attendance_session_id,c.config_version,d.config_version AS current_version,d.active AS device_active FROM identity_assertions a JOIN device_contexts c ON c.id=a.context_id JOIN devices d ON d.id=a.device_id WHERE a.id=$1 FOR UPDATE OF a,c', [assertionId]);
    if (identity.consumed_at || new Date(identity.expires_at) < new Date() || identity.purpose !== purpose || identity.context_status !== 'OPEN' || identity.config_version !== identity.current_version || !identity.device_active)
        reject(422, 'IDENTITY_EXPIRED', 'Lần xác thực hết hiệu lực hoặc sai ngữ cảnh.');
    const targets: Record<string, string> = { PARKING_ENTRY: 'parking_lot_id', PARKING_EXIT: 'parking_session_id', CANTEEN: 'order_id', ENROLLMENT: 'enrollment_student_id', ATTENDANCE: 'attendance_session_id' };
    if (targetId && identity[targets[purpose]] !== targetId)
        reject(403, 'CONTEXT_MISMATCH', 'Lần quét không thuộc thao tác này.');
    const student = await one(db, 'SELECT s.active,u.status FROM students s JOIN users u ON u.id=s.user_id WHERE s.id=$1', [identity.student_id]);
    if (!student.active || student.status !== 'ACTIVE')
        reject(422, 'STUDENT_INACTIVE', 'Sinh viên đã bị khóa.');
    if (identity.card_id && !await optional(db, "SELECT id FROM rfid_cards WHERE id=$1 AND status='ACTIVE' AND (expires_at IS NULL OR expires_at>now())", [identity.card_id]))
        reject(422, 'CARD_NOT_ACTIVE', 'Thẻ đã bị khóa.');
    if (!identity.card_id && !identity.credential_hmac && !await hasFaceProfile(db, identity.student_id, purpose === 'CANTEEN' ? 'CANTEEN' : purpose === 'ATTENDANCE' ? 'ATTENDANCE' : 'PARKING', identity.source))
        reject(422, 'CONSENT_REQUIRED', 'Hồ sơ hoặc đồng ý nhận diện không còn hiệu lực.');
    await db.query('UPDATE identity_assertions SET consumed_at=now() WHERE id=$1', [assertionId]);
    await db.query("UPDATE device_contexts SET status='CONSUMED' WHERE id=$1", [identity.context_id]);
    return identity;
}
export async function hasFaceProfile(db: Db, studentId: string, purpose: string, source: 'DEMO' | 'REAL') { return !!await optional(db, "SELECT p.id FROM biometric_profiles p JOIN biometric_consents c ON c.id=p.consent_id WHERE p.student_id=$1 AND p.purpose=$2 AND (p.source=$3 OR p.source='REAL') AND p.status='ACTIVE' AND c.revoked_at IS NULL AND c.student_id=p.student_id AND c.purpose=p.purpose", [studentId, purpose, source]); }
export const hasDemoProfile = (db: Db, studentId: string, purpose: string) => hasFaceProfile(db, studentId, purpose, 'DEMO');
export async function demoFace(db: Db, a: Actor, body: unknown): Promise<Result> {
    requirePermission(a, 'simulator.use');
    const b = fields(body, ['contextId', 'studentFixtureId', 'scenario']);
    const ctx = await one(db, "SELECT * FROM device_contexts WHERE id=$1 AND status='OPEN' AND expires_at>now()", [uuid(b.contextId)]);
    const student = await one(db, 'SELECT s.*,u.status FROM students s JOIN users u ON u.id=s.user_id WHERE s.id=$1', [uuid(b.studentFixtureId)]);
    if (!student.active || student.status !== 'ACTIVE')
        reject(422, 'STUDENT_INACTIVE', 'Sinh viên fixture đã bị khóa.');
    if (ctx.purpose === 'PARKING_ENTRY' && await optional(db, "SELECT 1 FROM campus.parking_sessions WHERE student_id=$1 AND status IN('PENDING_ENTRY','ACTIVE','EXIT_PENDING','EXCEPTION')", [student.id]))
        reject(422, 'VEHICLE_ALREADY_IN_LOT', 'Sinh viên đã có xe đang gửi trong bãi. Không thể dùng khuôn mặt gửi thêm xe!');
    const purpose = ctx.purpose === 'ATTENDANCE' ? 'ATTENDANCE' : ctx.purpose === 'CANTEEN' ? 'CANTEEN' : 'PARKING';
    if (ctx.purpose === 'ENROLLMENT')
        reject(422, 'REAL_RFID_REQUIRED', 'Cấp thẻ bắt buộc quét RFID thật.');
    if (!await hasDemoProfile(db, student.id, purpose))
        reject(422, 'CONSENT_REQUIRED', 'Fixture chưa đồng ý xử lý nhận diện cho mục đích này.');
    const correlation = { eventId: id(), deviceId: ctx.device_id, timestamp: new Date().toISOString() };
    const capture = await new DemoCameraProvider().capture(correlation);
    const result = await new DemoFaceProvider({ studentId: student.id, scenario: str(b.scenario, 30) }).recognize({ ...correlation, captureRef: capture.captureId, allowedStudentIds: [student.id], purpose });
    await db.query("INSERT INTO simulation_events VALUES($1,$2,$3,$4,$5,'DEMO',$6,now())", [result.eventId, a.id, ctx.device_id, ctx.id, b.scenario, result]);
    if (result.recognitionStatus !== 'MATCH' || result.livenessStatus !== 'PASS')
        return { status: 422, error: { code: result.livenessStatus === 'FAIL' ? 'LIVENESS_FAILED' : 'FACE_NOT_RECOGNIZED', message: 'Face DEMO không đủ điều kiện nhận diện.', details: result } };
    const identity = await assertion(db, ctx, student.id, 'DEMO');
    return { ...identity, data: { ...identity.data as object, faceResult: result } };
}
export async function demoOcr(db: Db, a: Actor, body: unknown) {
    requirePermission(a, 'simulator.use');
    const b = fields(body, ['contextId', 'rawText', 'scenario']);
    const ctx = await one(db, "SELECT * FROM device_contexts WHERE id=$1 AND status='OPEN' AND expires_at>now()", [uuid(b.contextId)]);
    if (!['PARKING_ENTRY', 'PARKING_EXIT'].includes(ctx.purpose))
        reject(422, 'CONTEXT_MISMATCH', 'OCR chỉ dùng trong ngữ cảnh gửi xe.');
    const result = await new DemoOCRProvider({ rawText: str(b.rawText, 30), scenario: str(b.scenario, 30) }).recognize({ eventId: id(), deviceId: ctx.device_id, timestamp: new Date().toISOString(), captureRef: null });
    const observationId = id();
    await db.query("INSERT INTO ocr_observations(id,context_id,raw_text,normalized_plate,confidence,source,status) VALUES($1,$2,$3,$4,$5,'DEMO',$6)", [observationId, ctx.id, result.rawText, result.normalizedPlate, result.confidence, result.recognitionStatus]);
    await audit(db, a, 'OCR_DEMO', observationId);
    return { id: observationId, ...result };
}
