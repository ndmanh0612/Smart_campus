import { Pool } from 'pg';
import { seed } from './src/database.ts';
import { loadConfig } from './src/platform.ts';
const cfg = loadConfig(process.env);
if (!process.env.MIGRATION_DATABASE_URL)
    throw Error('MIGRATION_DATABASE_URL required for seed.');
const pool = new Pool({ connectionString: process.env.MIGRATION_DATABASE_URL });
try {
    const result = await seed(pool, { password: process.env.SEED_PASSWORD ?? '', pin: process.env.SEED_PIN ?? '', cardKey: cfg.cardKey, deviceToken: process.env.SEED_DEVICE_TOKEN ?? '' });
    process.stdout.write(JSON.stringify({ seed: 'OK', ...result, rfidCards: 'Không tạo thẻ giả; cần enrollment bằng MFRC522 thật.' }) + '\n');
}
finally {
    await pool.end();
}
