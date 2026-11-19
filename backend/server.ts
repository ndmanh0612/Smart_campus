import { Pool } from 'pg';
import { createCampusApp } from './src/app.ts';
import { loadConfig } from './src/platform.ts';
import { attachRealtime, startWorker } from './src/worker.ts';
import { startMqttBridge } from './src/mqtt-bridge.ts';
if (!process.env.DATABASE_URL)
    throw Error('DATABASE_URL required');
const pool = new Pool({ connectionString: process.env.DATABASE_URL, max: 10, connectionTimeoutMillis: 3000 });
pool.on('error', (err) => {
    console.warn('[DATABASE_POOL] Idle client error (handled):', err.message);
});
const cfg = loadConfig(process.env);
const stopMqtt = startMqttBridge(process.env, 'http://127.0.0.1:' + (process.env.PORT ?? '8081'));
const server = createCampusApp(pool, cfg).listen(Number(process.env.PORT ?? 8081), process.env.HOST ?? '127.0.0.1', () => process.stdout.write(JSON.stringify({ listening: true, port: Number(process.env.PORT ?? 8081), environment: cfg.env, rfid: 'REAL', face: 'DEMO', payment: 'MOCK' }) + '\n'));
const realtime = attachRealtime(server, pool, cfg);
const stopWorker = startWorker(pool, realtime.publish);
let closing = false;
for (const signal of ['SIGINT', 'SIGTERM'])
    process.on(signal, () => {
        if (closing)
            return;
        closing = true;
        stopMqtt();
        void (async () => { await stopWorker(); await new Promise<void>(resolve => realtime.io.close(() => resolve())); await new Promise<void>(resolve => server.close(() => resolve())); await pool.end(); })().catch(() => { process.exitCode = 1; });
    });
