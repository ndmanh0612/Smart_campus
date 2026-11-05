import {Pool} from 'pg';
import {migrate,grantRuntime,seed} from './src/database.ts';
import {loadConfig} from './src/platform.ts';
const cfg=loadConfig(process.env);
if(!process.env.MIGRATION_DATABASE_URL||(process.env.RUNTIME_DATABASE_PASSWORD??'').length<32)throw Error('Owner URL and random runtime password required.');
const pool=new Pool({connectionString:process.env.MIGRATION_DATABASE_URL});
try{
  await migrate(pool);await grantRuntime(pool);
  if(!(await pool.query("SELECT 1 FROM pg_roles WHERE rolname='smartcampus_app'")).rowCount)await pool.query('CREATE ROLE smartcampus_app LOGIN');
  const password=process.env.RUNTIME_DATABASE_PASSWORD!;
  await pool.query("ALTER ROLE smartcampus_app PASSWORD '"+password.replace(/'/g,"''")+"'");await pool.query('GRANT smartcampus_runtime TO smartcampus_app');
  await seed(pool,{password:process.env.SEED_PASSWORD??'',pin:process.env.SEED_PIN??'',cardKey:cfg.cardKey,deviceToken:process.env.SEED_DEVICE_TOKEN??''});
  process.stdout.write('Smart Campus bootstrap OK (synthetic seed, no RFID card, no real money).\n');
}finally{await pool.end();}
