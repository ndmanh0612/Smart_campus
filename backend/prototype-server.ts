// Preserved week-1 entry point; not mounted by the Smart Campus runtime.
import {Pool} from 'pg';
import {createApp} from './app.ts';
if(!process.env.DATABASE_URL)throw Error('DATABASE_URL required');
const pool=new Pool({connectionString:process.env.DATABASE_URL,max:10,connectionTimeoutMillis:3000});
const server=createApp(pool,process.env.CARD_HMAC_SECRET??'').listen(Number(process.env.PORT??8081),process.env.HOST??'127.0.0.1');
for(const signal of ['SIGINT','SIGTERM'])process.on(signal,()=>server.close(()=>void pool.end()));
