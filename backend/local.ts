import { Pool } from 'pg';
import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { resolve } from 'node:path';
import { randomBytes } from 'node:crypto';
import { migrate, grantRuntime, seed } from './src/database.ts';
import { token } from './src/platform.ts';
const url = process.env.CAMPUS_LOCAL_DATABASE_URL;
if (!url || new URL(url).pathname !== '/smartcampus_local' || new URL(url).hostname !== '127.0.0.1')
    throw Error('Only the isolated smartcampus_local database is allowed.');
const work = resolve(import.meta.dirname, '../.work');
await mkdir(work, { recursive: true });
const file = resolve(work, 'campus-local.json');
let c: Record<string, string>;
try {
    c = JSON.parse(await readFile(file, 'utf8'));
}
catch (e) {
    if ((e as NodeJS.ErrnoException).code !== 'ENOENT')
        throw e;
    c = { password: token(), pin: String(100000 + randomBytes(4).readUInt32BE() % 900000), deviceToken: token(), cardKey: token(), mockSecret: token(), databasePassword: token() };
    await writeFile(file, JSON.stringify(c, null, 2), { mode: 0o600 });
}
const pool = new Pool({ connectionString: url });
try {
    await migrate(pool);
    await grantRuntime(pool);
    const exists = await pool.query("SELECT 1 FROM pg_roles WHERE rolname='smartcampus_local_app'");
    if (!exists.rowCount)
        await pool.query("CREATE ROLE smartcampus_local_app LOGIN");
    // Random base64url secret is still quoted as a SQL literal, never interpolated into a shell command.
    await pool.query("ALTER ROLE smartcampus_local_app PASSWORD '" + c.databasePassword.replace(/'/g, "''") + "'");
    await pool.query('GRANT smartcampus_runtime TO smartcampus_local_app');
    const seeded = await seed(pool, { password: c.password, pin: c.pin, cardKey: c.cardKey, deviceToken: c.deviceToken });
    const runtimeUrl = new URL(url);
    runtimeUrl.username = 'smartcampus_local_app';
    runtimeUrl.password = c.databasePassword;
    const env = `APP_ENV=development\nDATABASE_URL=${runtimeUrl.toString()}\nCARD_HMAC_SECRET=${c.cardKey}\nMOCK_CALLBACK_SECRET=${c.mockSecret}\nPUBLIC_ORIGIN=http://localhost:8081\nHOST=127.0.0.1\nPORT=8081\nSIMULATOR_ENABLED=true\n`;
    await writeFile(resolve(work, 'campus.env'), env, { mode: 0o600 });
    await writeFile(resolve(work, 'campus-access.txt'), `SMART CAMPUS — CHỈ DÙNG LOCAL/THỬ NGHIỆM\nURL: http://localhost:8081\nTài khoản: admin, student, student2, lecturer, parking, canteen @campus.test\nMật khẩu chung fixture: ${c.password}\nPIN ví fixture: ${c.pin}\nDEVICE_ID: ${seeded.readerId}\nDEVICE_TOKEN: ${c.deviceToken}\nChưa cấp thẻ: dùng RFID_ENROLLMENT và quét MFRC522 thật.\nTệp chứa secret, không chia sẻ/commit/đưa vào báo cáo.\n`, { mode: 0o600 });
    process.stdout.write('Local migration/seed hoàn tất. Tài khoản và cấu hình ở source/.work/campus-access.txt; không in secret lên log.\n');
}
finally {
    await pool.end();
}
