import type { Pool } from 'pg';
import type { Request } from 'express';
import { ApiError, audit, fields, hash, id, one, optional, passwordHash, rateLimit, reject, str, token, transaction, verifyPassword, type Actor, type Db, type Result } from './platform.ts';
export async function actorForToken(pool: Pool, value: string): Promise<Actor> {
    if (!/^Bearer [\w-]{40,100}$/.test(value))
        reject(401, 'UNAUTHORIZED', 'Vui lòng đăng nhập.');
    const result = await pool.query(`SELECT u.id,s.id AS session_id,s.authenticated_at,st.id AS student_id,l.id AS lecturer_id,
    coalesce((SELECT array_agg(role) FROM campus.user_roles WHERE user_id=u.id),'{}') AS roles,
    coalesce((SELECT array_agg(DISTINCT permission) FROM campus.role_permissions p JOIN campus.user_roles r ON r.role=p.role WHERE r.user_id=u.id),'{}') AS permissions
    FROM campus.auth_sessions s JOIN campus.users u ON u.id=s.user_id LEFT JOIN campus.students st ON st.user_id=u.id
    LEFT JOIN campus.lecturers l ON l.user_id=u.id WHERE s.access_hash=$1 AND s.revoked_at IS NULL AND s.access_expires_at>now() AND u.status='ACTIVE'`, [hash(value.slice(7))]);
    const row = result.rows[0];
    if (!row)
        reject(401, 'UNAUTHORIZED', 'Phiên đăng nhập không hợp lệ hoặc đã hết hạn.');
    return { id: row.id, sessionId: row.session_id, roles: row.roles, permissions: row.permissions, studentId: row.student_id, lecturerId: row.lecturer_id, authenticatedAt: row.authenticated_at };
}
async function newSession(db: Db, userId: string, familyId = id(), authenticatedAt = new Date()) {
    const accessToken = token(), refreshToken = token();
    const sessionId = id();
    await db.query("INSERT INTO auth_sessions(id,user_id,access_hash,refresh_hash,family_id,access_expires_at,refresh_expires_at,authenticated_at) VALUES($1,$2,$3,$4,$5,now()+interval '15 minutes',now()+interval '7 days',$6)", [sessionId, userId, hash(accessToken), hash(refreshToken), familyId, authenticatedAt]);
    return { accessToken, refreshToken, expiresIn: 900 };
}
export async function login(pool: Pool, req: Request) {
    const b = fields(req.body, ['email', 'password']);
    const email = str(b.email, 200).toLowerCase(), password = str(b.password, 200);
    await rateLimit(pool, 'login:' + req.ip, 10);
    const result = await pool.query('SELECT * FROM campus.users WHERE email=$1', [email]);
    const user = result.rows[0];
    // Equal-cost hashing for unknown users avoids an immediate username timing oracle.
    const dummy = await passwordHash('unknown-user-timing-pad');
    if (!await verifyPassword(password, user?.password_hash ?? dummy) || !user || user.status !== 'ACTIVE')
        reject(401, 'INVALID_CREDENTIALS', 'Email hoặc mật khẩu không đúng.');
    return transaction(pool, async (db) => { const credentials = await newSession(db, user.id); await audit(db, null, 'AUTH_LOGIN', user.id); return credentials; });
}

export async function demoLogin(pool: Pool, rawEmail: string) {
    const email = str(rawEmail, 200).toLowerCase();
    const result = await pool.query("SELECT * FROM campus.users WHERE email=$1 AND status='ACTIVE'", [email]);
    const user = result.rows[0];
    if (!user) {
        reject(404, 'USER_NOT_FOUND', 'Không tìm thấy tài khoản người dùng.');
    }
    return transaction(pool, async (db) => {
        const credentials = await newSession(db, user.id);
        await audit(db, null, 'AUTH_DEMO_LOGIN', user.id);
        return credentials;
    });
}
export async function refresh(pool: Pool, raw: string): Promise<Result> {
    return transaction(pool, async (db) => {
        const session = await optional(db, 'SELECT * FROM auth_sessions WHERE refresh_hash=$1 FOR UPDATE', [hash(raw)]);
        if (!session)
            return { status: 401, error: { code: 'INVALID_REFRESH', message: 'Phiên làm mới không hợp lệ.' } };
        if (session.revoked_at || new Date(session.refresh_expires_at) < new Date()) {
            await db.query('UPDATE auth_sessions SET revoked_at=now() WHERE family_id=$1', [session.family_id]);
            return { status: 401, error: { code: 'REFRESH_REUSED', message: 'Phiên đã bị thu hồi. Vui lòng đăng nhập lại.' } };
        }
        const user = await one(db, 'SELECT status FROM users WHERE id=$1', [session.user_id]);
        if (user.status !== 'ACTIVE')
            return { status: 401, error: { code: 'ACCOUNT_DISABLED', message: 'Tài khoản đã khóa.' } };
        await db.query('UPDATE auth_sessions SET revoked_at=now() WHERE id=$1', [session.id]);
        return { data: await newSession(db, session.user_id, session.family_id, session.authenticated_at) };
    });
}
export async function revokeSessions(db: Db, a: Actor) { await db.query('UPDATE auth_sessions SET revoked_at=now() WHERE family_id=(SELECT family_id FROM auth_sessions WHERE id=$1)', [a.sessionId]); }
export async function profile(db: Db, a: Actor) {
    return one(db, `SELECT u.id,u.email,u.name,u.status,st.id AS "studentId",st.student_code AS "studentCode",st.synthetic,
  l.id AS "lecturerId",$2::text[] AS roles,$3::text[] AS permissions FROM users u LEFT JOIN students st ON st.user_id=u.id LEFT JOIN lecturers l ON l.user_id=u.id WHERE u.id=$1`, [a.id, a.roles, a.permissions]);
}
export async function checkPin(db: Db, a: Actor, pin: unknown): Promise<Result | null> {
    if (!a.studentId)
        reject(403, 'STUDENT_REQUIRED', 'Chỉ sinh viên được xác nhận ví của mình.');
    const value = str(pin, 12, 4);
    if (!/^\d{4,12}$/.test(value))
        reject(400, 'INVALID_PIN', 'PIN gồm 4–12 chữ số.');
    const security = await optional(db, 'SELECT * FROM wallet_security_settings WHERE student_id=$1 FOR UPDATE', [a.studentId]);
    if (!security)
        return { status: 422, error: { code: 'PIN_REQUIRED', message: 'Bạn cần đặt PIN ví trước.' } };
    if (security.locked_until && new Date(security.locked_until) > new Date())
        return { status: 429, error: { code: 'PIN_LOCKED', message: 'PIN tạm khóa trong 15 phút.' } };
    if (!await verifyPassword(value, security.pin_hash)) {
        await db.query("UPDATE wallet_security_settings SET failed_count=CASE WHEN locked_until<now() THEN 1 ELSE failed_count+1 END,locked_until=CASE WHEN failed_count>=4 AND (locked_until IS NULL OR locked_until>now()) THEN now()+interval '15 minutes' ELSE NULL END WHERE student_id=$1", [a.studentId]);
        return { status: 422, error: { code: 'INVALID_PIN', message: 'PIN không đúng.' } };
    }
    await db.query('UPDATE wallet_security_settings SET failed_count=0,locked_until=NULL WHERE student_id=$1', [a.studentId]);
    return null;
}
export function safeError(error: unknown): ApiError {
    if (error instanceof ApiError)
        return error;
    const e = error as {
        code?: string;
        type?: string;
        message?: string;
    };
    if (e.type === 'entity.too.large')
        return new ApiError(413, 'BODY_TOO_LARGE', 'Dữ liệu gửi lên quá lớn.');
    if (e.type === 'entity.parse.failed')
        return new ApiError(400, 'INVALID_JSON', 'JSON không hợp lệ.');
    if (e.code === '23505')
        return new ApiError(409, 'RESOURCE_CONFLICT', 'Dữ liệu đã tồn tại hoặc có thao tác đang xử lý.');
    if (e.code === '23503' || e.code === '23514' || e.code === '22P02')
        return new ApiError(422, 'DATA_CONSTRAINT', 'Dữ liệu không thỏa ràng buộc nghiệp vụ.');
    if (e.message === 'INSUFFICIENT_POINTS')
        return new ApiError(422, 'INSUFFICIENT_POINTS', 'Ví chưa đủ point.');
    if (e.message === 'REFUND_EXCEEDS_ORIGINAL')
        return new ApiError(422, 'REFUND_EXCEEDS_ORIGINAL', 'Tổng hoàn vượt số point đã thu.');
    return new ApiError(503, 'DEPENDENCY_UNAVAILABLE', 'Hệ thống tạm chưa xử lý được. Vui lòng tra trạng thái trước khi thử lại.');
}
