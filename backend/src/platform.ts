import { createHash, createHmac, randomBytes, randomUUID, scrypt, timingSafeEqual } from 'node:crypto';
import type { Pool, PoolClient } from 'pg';
import type { Request, Response, NextFunction } from 'express';
export type Db = PoolClient;
export type Actor = {
    id: string;
    roles: string[];
    permissions: string[];
    studentId: string | null;
    lecturerId: string | null;
    sessionId: string;
    authenticatedAt: Date;
};
export type Result = {
    status?: number;
    data?: unknown;
    error?: {
        code: string;
        message: string;
        details?: unknown;
    };
};
export class ApiError extends Error {
    status: number;
    code: string;
    details?: unknown;
    constructor(status: number, code: string, message: string, details?: unknown) { super(message); this.status = status; this.code = code; this.details = details; }
}
export const reject = (status: number, code: string, message: string, details?: unknown): never => { throw new ApiError(status, code, message, details); };
export const hash = (value: string) => createHash('sha256').update(value).digest('hex');
export const uidHash = (uid: string, key: string) => createHmac('sha256', key).update(uid.toUpperCase()).digest('hex');
export const token = () => randomBytes(32).toString('base64url');
export const id = () => randomUUID();
export async function passwordHash(value: string) {
    const salt = randomBytes(16).toString('hex');
    const derived = await new Promise<Buffer>((resolve, reject) => scrypt(value, salt, 32, { N: 32768, r: 8, p: 1, maxmem: 64 * 1024 * 1024 }, (e, b) => e ? reject(e) : resolve(b)));
    return `scrypt-v1:${salt}:${derived.toString('hex')}`;
}
export async function verifyPassword(value: string, encoded: string) {
    const [version, salt, expected] = encoded.split(':');
    if (version !== 'scrypt-v1' || !salt || !expected)
        return false;
    const derived = await new Promise<Buffer>((resolve, reject) => scrypt(value, salt, 32, { N: 32768, r: 8, p: 1, maxmem: 64 * 1024 * 1024 }, (e, b) => e ? reject(e) : resolve(b)));
    const wanted = Buffer.from(expected, 'hex');
    return wanted.length === derived.length && timingSafeEqual(wanted, derived);
}
export function fields(value: unknown, allowed: string[], required: string[] = allowed): Record<string, unknown> {
    if (!value || typeof value !== 'object' || Array.isArray(value))
        reject(400, 'INVALID_BODY', 'Dữ liệu gửi lên không hợp lệ.');
    const b = value as Record<string, unknown>;
    if (Object.keys(b).some(k => !allowed.includes(k)) || required.some(k => b[k] === undefined))
        reject(400, 'INVALID_FIELDS', 'Thiếu trường bắt buộc hoặc có trường không được phép.');
    return b;
}
export function str(value: unknown, max = 200, min = 1): string {
    if (typeof value !== 'string' || value.trim().length < min || value.length > max)
        reject(400, 'INVALID_TEXT', 'Giá trị văn bản không hợp lệ.');
    return (value as string).trim();
}
export function uuid(value: unknown) {
    const s = str(value, 36);
    if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(s))
        reject(400, 'INVALID_ID', 'ID không hợp lệ.');
    return s.toLowerCase();
}
export function integer(value: unknown, min = 1, max = 1000000) {
    if (typeof value !== 'number' || !Number.isSafeInteger(value) || value < min || value > max)
        reject(400, 'INVALID_NUMBER', 'Số nguyên không hợp lệ.');
    return value as number;
}
export function points(value: unknown, max = 1000000000n) {
    if (typeof value !== 'string' || !/^[1-9][0-9]{0,12}$/.test(value) || BigInt(value) > max)
        reject(400, 'INVALID_AMOUNT', 'Số point phải là chuỗi số nguyên dương trong hạn mức.');
    return value as string;
}
export function choice<T extends string>(value: unknown, values: readonly T[]): T {
    if (!values.includes(value as T))
        reject(400, 'INVALID_CHOICE', 'Lựa chọn không hợp lệ.');
    return value as T;
}
export function bool(value: unknown) {
    if (typeof value !== 'boolean')
        reject(400, 'INVALID_BOOLEAN', 'Giá trị boolean không hợp lệ.');
    return value as boolean;
}
export const one = async (db: Db, sql: string, args: unknown[] = []) => { const r = await db.query(sql, args); return r.rows[0] ?? reject(404, 'NOT_FOUND', 'Không tìm thấy dữ liệu.'); };
export const optional = async (db: Db, sql: string, args: unknown[] = []) => (await db.query(sql, args)).rows[0];
export async function transaction<T>(pool: Pool, fn: (db: Db) => Promise<T>): Promise<T> {
    const db = await pool.connect();
    try {
        await db.query('BEGIN');
        await db.query("SET LOCAL search_path=campus,public; SET LOCAL lock_timeout='5s'; SET LOCAL statement_timeout='15s'");
        const result = await fn(db);
        await db.query('COMMIT');
        return result;
    }
    catch (e) {
        await db.query('ROLLBACK').catch(() => { });
        throw e;
    }
    finally {
        db.release();
    }
}
function canonical(value: unknown): string {
    if (Array.isArray(value))
        return '[' + value.map(canonical).join(',') + ']';
    if (value && typeof value === 'object')
        return '{' + Object.entries(value).filter(([k]) => !['pin', 'password', 'newPin', 'oldPin'].includes(k)).sort(([a], [b]) => a.localeCompare(b)).map(([k, v]) => JSON.stringify(k) + ':' + canonical(v)).join(',') + '}';
    return JSON.stringify(value) ?? 'null';
}
export async function mutate(pool: Pool, scope: string, key: unknown, body: unknown, fn: (db: Db) => Promise<Result>): Promise<Result> {
    const k = str(key, 128, 16);
    if (!/^[\x21-\x7e]+$/.test(k))
        reject(400, 'INVALID_KEY', 'Idempotency-Key không hợp lệ.');
    return transaction(pool, async (db) => {
        await db.query('SELECT pg_advisory_xact_lock(hashtextextended($1,0))', [scope + ':' + k]);
        const prior = await optional(db, 'SELECT * FROM idempotency_records WHERE scope=$1 AND key=$2', [scope, k]);
        const payloadHash = hash(canonical(body));
        if (prior) {
            if (prior.payload_hash !== payloadHash)
                reject(409, 'IDEMPOTENCY_CONFLICT', 'Khóa đã dùng với nội dung khác.');
            return { status: prior.status, ...prior.response };
        }
        const result = await fn(db);
        const status = result.status ?? 200;
        const storedData = result.data && typeof result.data === 'object' && 'deviceCredential' in result.data ? { ...result.data, deviceCredential: null, credentialAlreadyIssued: true } : result.data;
        const response = { data: storedData, error: result.error };
        await db.query('INSERT INTO idempotency_records(scope,key,payload_hash,status,response) VALUES($1,$2,$3,$4,$5)', [scope, k, payloadHash, status, response]);
        return result;
    });
}
export function camel(value: unknown): unknown {
    if (value instanceof Date)
        return value.toISOString();
    if (Array.isArray(value))
        return value.map(camel);
    if (value && typeof value === 'object')
        return Object.fromEntries(Object.entries(value).map(([k, v]) => [k.replace(/_([a-z])/g, (_, c: string) => c.toUpperCase()), camel(v)]));
    return value;
}
export function send(res: Response, result: Result) { res.status(result.status ?? 200).json(camel({ ...('error' in result ? { error: result.error } : { data: result.data }), requestId: res.getHeader('X-Request-Id') })); }
export const handler = (fn: (req: Request, res: Response) => Promise<unknown>) => (req: Request, res: Response, next: NextFunction) => { void fn(req, res).catch(next); };
export function requireRole(a: Actor, ...roles: string[]) {
    if (!a.roles.some(r => roles.includes(r)))
        reject(403, 'FORBIDDEN', 'Bạn không có quyền thực hiện thao tác này.');
}
export function requirePermission(a: Actor, permission: string) {
    if (!a.permissions.includes(permission))
        reject(403, 'FORBIDDEN', 'Bạn chưa được cấp quyền thao tác này.');
}
export function expected(actual: number, input: unknown) {
    if (integer(input) !== actual)
        reject(409, 'VERSION_CONFLICT', 'Dữ liệu đã thay đổi, vui lòng tải lại.');
}
export async function audit(db: Db, a: Actor | null, action: string, resourceId: string | null, reason?: string, metadata: unknown = {}, deviceId: string | null = null) { await db.query('INSERT INTO audit_logs(id,actor_id,device_id,action,resource_id,reason,metadata) VALUES($1,$2,$3,$4,$5,$6,$7)', [id(), a?.id ?? null, deviceId, action, resourceId, reason ?? null, metadata]); }
export async function emit(db: Db, type: string, aggregateId: string, payload: unknown = {}, recipient: string | null = null) { await db.query('INSERT INTO outbox_events(id,type,aggregate_id,recipient_user_id,payload) VALUES($1,$2,$3,$4,$5)', [id(), type, aggregateId, recipient, payload]); }
export async function notify(db: Db, studentId: string, type: string, message: string, resourceId: string) { const s = await one(db, 'SELECT user_id FROM students WHERE id=$1', [studentId]); await db.query('INSERT INTO notifications(id,recipient_user_id,type,message,resource_id) VALUES($1,$2,$3,$4,$5)', [id(), s.user_id, type, message, resourceId]); await emit(db, type, resourceId, { message }, s.user_id); }
export async function rateLimit(pool: Pool, scope: string, limit: number, seconds = 60) {
    const bucket = Math.floor(Date.now() / 1000 / seconds);
    const r = await pool.query('INSERT INTO campus.rate_limit_counters(scope,bucket,count) VALUES($1,$2,1) ON CONFLICT(scope,bucket) DO UPDATE SET count=campus.rate_limit_counters.count+1 RETURNING count', [scope, bucket]);
    if (r.rows[0].count > limit)
        reject(429, 'RATE_LIMITED', 'Thao tác quá nhanh, vui lòng chờ rồi thử lại.');
}
export type CampusConfig = {
    env: 'development' | 'test';
    cardKey: string;
    mockSecret: string;
    origin: string;
    simulator: boolean;
};
export function loadConfig(env: NodeJS.ProcessEnv): CampusConfig {
    const mode = env.APP_ENV ?? 'development';
    if (!['development', 'test'].includes(mode))
        throw Error('MVP chỉ hỗ trợ development/test; production từ chối DEMO/MOCK/SIMULATOR.');
    for (const [name, wanted] of Object.entries({ RFID_MODE: 'REAL', FACE_PROVIDER: 'DEMO', LIVENESS_PROVIDER: 'DEMO', CAMERA_PROVIDER: 'DEMO', OCR_PROVIDER: 'DEMO', GATE_PROVIDER: 'SIMULATOR', PAYMENT_PROVIDER: 'MOCK' }))
        if ((env[name] ?? wanted) !== wanted)
            throw Error(`Provider ${name} chưa được triển khai; không tự fallback.`);
    if ((env.CARD_HMAC_SECRET ?? '').length < 32 || (env.MOCK_CALLBACK_SECRET ?? '').length < 32)
        throw Error('CARD_HMAC_SECRET và MOCK_CALLBACK_SECRET phải >=32 ký tự.');
    return { env: mode as CampusConfig['env'], cardKey: env.CARD_HMAC_SECRET!, mockSecret: env.MOCK_CALLBACK_SECRET!, origin: env.PUBLIC_ORIGIN ?? 'http://localhost:8081', simulator: env.SIMULATOR_ENABLED !== 'false' };
}
