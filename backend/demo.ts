import {Pool} from 'pg';
import {randomBytes,randomUUID} from 'node:crypto';
import {readFileSync,writeFileSync} from 'node:fs';
import assert from 'node:assert/strict';
import {createApp,cardHash,digest} from './app.ts';

const url=process.env.DEMO_DATABASE_URL;
if(!url||new URL(url).pathname!=='/smartcard_week1_demo')throw Error('Use dedicated smartcard_week1_demo database');
const pool=new Pool({connectionString:url,max:25});
const token=randomBytes(32).toString('hex'),key=randomBytes(32).toString('hex');
const student=randomUUID(),device=randomUUID(),cls=randomUUID(),session=randomUUID(),card=randomUUID();
const checks:Record<string,unknown>[]=[];
const server=createApp(pool,key).listen(0,'127.0.0.1');
try{
 await new Promise<void>(r=>server.once('listening',r));
 const address=server.address();if(!address||typeof address==='string')throw Error('Missing local port');
 const base=`http://127.0.0.1:${address.port}`;
 if(!(await pool.query("SELECT to_regclass('schema_migrations') AS present")).rows[0].present)
  await pool.query(readFileSync(new URL('../database/001.sql',import.meta.url),'utf8'));
 const c=await pool.connect();
 try{
  await c.query('BEGIN');
  await c.query('INSERT INTO students(id,student_code) VALUES($1,$2)',[student,'DEMO-'+student]);
  await c.query('INSERT INTO devices(id,name,token_hash) VALUES($1,$2,$3)',[device,'Demo simulated reader',digest(token)]);
  await c.query("INSERT INTO student_cards(id,student_id,uid_hmac,status) VALUES($1,$2,$3,'ACTIVE')",[card,student,cardHash('DEADBEEF',key)]);
  await c.query('INSERT INTO classes VALUES($1,$2)',[cls,'DEMO-'+cls]);
  await c.query("INSERT INTO class_sessions VALUES($1,$2,'OPEN',now()+interval '1 hour')",[session,cls]);
  await c.query('INSERT INTO session_roster VALUES($1,$2)',[session,student]);
  await c.query('INSERT INTO session_devices(session_id,device_id) VALUES($1,$2)',[session,device]);
  await c.query('COMMIT');
 }catch(e){await c.query('ROLLBACK');throw e;}finally{c.release();}
 const post=async(eventId:string)=>{
  const r=await fetch(base+'/v1/device-events',{method:'POST',headers:{Authorization:'Bearer '+token,'Content-Type':'application/json'},body:JSON.stringify({event_id:eventId,card_uid:'DEADBEEF',purpose:'ATTENDANCE'})});
  return {status:r.status,body:await r.json()};
 };
 const firstId=randomUUID(),first=await post(firstId);assert.equal(first.status,201);
 checks.push({step:1,action:'Simulated valid card',actual:first,status:'PASS'});
 const retry=await post(firstId);assert.deepEqual(retry,first);
 checks.push({step:2,action:'Lost ACK retry, same event',same_response:true,status:'PASS'});
 const concurrent=await Promise.all(Array.from({length:20},()=>post(randomUUID())));
 assert.ok(concurrent.every(r=>r.body.outcome==='ALREADY_RECORDED'));
 const count=Number((await pool.query('SELECT count(*) FROM attendance_records WHERE session_id=$1',[session])).rows[0].count);
 assert.equal(count,1);checks.push({step:3,action:'20 additional concurrent simulated scans',attendance_count:count,status:'PASS'});
 await pool.query("UPDATE student_cards SET status='REVOKED' WHERE id=$1",[card]);
 const revoked=await post(randomUUID());assert.equal(revoked.body.outcome,'CARD_NOT_ACTIVE');
 checks.push({step:4,action:'Revoked card',actual:revoked,status:'PASS'});
 await pool.query("UPDATE class_sessions SET status='CLOSED' WHERE id=$1",[session]);
 const closed=await post(randomUUID());assert.equal(closed.body.outcome,'SESSION_NOT_OPEN');
 checks.push({step:5,action:'Closed session',actual:closed,status:'PASS'});
 const ledger=Number((await pool.query('SELECT count(*) FROM ledger_transactions')).rows[0].count);
 assert.equal(ledger,0);checks.push({step:6,action:'Attendance does not post payment',ledger_transactions:ledger,status:'PASS'});
 const report={timestamp_utc:new Date().toISOString(),mode:'LOCAL_SIMULATED_DEVICE_NOT_PHYSICAL_RFID',session_id:session,checks,all_passed:true};
 writeFileSync(new URL('../docs/evidence/demo-backend.json',import.meta.url),JSON.stringify(report,null,2));
 console.log(JSON.stringify(report,null,2));
}finally{
 // Keep only this run's synthetic data. No TRUNCATE, no modification to any existing run.
 try{await pool.query('UPDATE devices SET active=false WHERE id=$1',[device]);await pool.query('UPDATE session_devices SET released_at=now() WHERE device_id=$1',[device]);}finally{
  await new Promise<void>(r=>server.close(()=>r()));await pool.end();
 }
}
