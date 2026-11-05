import { Pool } from 'pg';
import { migrate, grantRuntime } from './src/database.ts';
if (!process.env.MIGRATION_DATABASE_URL)
    throw Error('MIGRATION_DATABASE_URL required; never migrate with runtime credentials.');
const pool = new Pool({ connectionString: process.env.MIGRATION_DATABASE_URL });
try {
    await migrate(pool);
    await grantRuntime(pool);
    process.stdout.write('Migration 002-campus và runtime grants: OK\n');
}
finally {
    await pool.end();
}
