import {test,before,after,beforeEach} from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID,randomBytes} from 'node:crypto';
import {readFileSync} from 'node:fs';
import {Pool} from 'pg';
import {createApp,cardHash,digest} from '../app.ts';
const url=process.env.TEST_DATABASE_URL;
if(!url||new URL(url).pathname!=='/smartcard_rebuild_test')throw Error('Dedicated test database required');
const pool=new Pool({connectionString:url,max:25});
const key=randomBytes(32).toString('hex'),token=randomBytes(32).toString('hex');
const ids=Array.from({length:6},()=>randomUUID());const [student,outsider,device,cls,session,card]=ids;
let server:ReturnType<ReturnType<typeof createApp>['listen']>,base='';
before(async()=>{
 const migrated=await pool.query("SELECT to_regclass('public.schema_migrations') AS present");
 if(!migrated.rows[0].present)await pool.query(readFileSync(new URL('../../database/001.sql',import.meta.url),'utf8'));
 server=createApp(pool,key).listen(0,'127.0.0.1');await new Promise<void>(r=>server.once('listening',r));
 const address=server.address();if(!address||typeof address==='string')throw Error('Port missing');base=`http://127.0.0.1:${address.port}`;
});
after(async()=>{await new Promise<void>(r=>server?.close(()=>r()));await pool.end();});
beforeEach(async()=>{
 await pool.query('TRUNCATE students,devices,classes,ledger_accounts CASCADE');
 await pool.query('INSERT INTO students(id,student_code) VALUES($1,\'S001\'),($2,\'S002\')',[student,outsider]);
 await pool.query('INSERT INTO devices VALUES($1,\'test-reader\',$2,true)',[device,digest(token)]);
 await pool.query('INSERT INTO student_cards(id,student_id,uid_hmac,status) VALUES($1,$2,$3,\'ACTIVE\')',[card,student,cardHash('DEADBEEF',key)]);
 await pool.query('INSERT INTO classes VALUES($1,\'AIOT\')',[cls]);
 await pool.query("INSERT INTO class_sessions VALUES($1,$2,'OPEN',now()+interval '1 hour')",[session,cls]);
 await pool.query('INSERT INTO session_roster VALUES($1,$2)',[session,student]);
 await pool.query('INSERT INTO session_devices(session_id,device_id) VALUES($1,$2)',[session,device]);
});
const event=()=>({event_id:randomUUID(),card_uid:'DEADBEEF',purpose:'ATTENDANCE'});
async function send(body:unknown,credential=token){const r=await fetch(base+'/v1/device-events',{method:'POST',headers:{Authorization:'Bearer '+credential,'Content-Type':'application/json'},body:JSON.stringify(body)});return {status:r.status,body:await r.json()};}
async function count(table:string){assert.ok(['attendance_records','device_events','ledger_transactions'].includes(table));return Number((await pool.query(`SELECT count(*) FROM ${table}`)).rows[0].count);}
test('valid RFID records once and changes no ledger',async()=>{const r=await send(event());assert.equal(r.status,201);assert.equal(r.body.status,'PRESENT');assert.equal(await count('attendance_records'),1);assert.equal(await count('ledger_transactions'),0);});
test('same event returns identical stored response',async()=>{const b=event();assert.deepEqual(await send(b),await send(b));assert.equal(await count('device_events'),1);});
test('same event different payload returns 409',async()=>{const b=event();await send(b);assert.equal((await send({...b,card_uid:'AABBCCDD'})).status,409);});
test('20 distinct concurrent scans create one attendance',async()=>{const results=await Promise.all(Array.from({length:20},()=>send(event())));assert.equal(results.filter(r=>r.status===201).length,1);assert.equal(await count('attendance_records'),1);});
test('20 concurrent identical retries create one event',async()=>{const b=event();const results=await Promise.all(Array.from({length:20},()=>send(b)));assert.ok(results.every(r=>r.status===201));assert.equal(await count('device_events'),1);});
test('revoked and expired cards rejected',async()=>{await pool.query("UPDATE student_cards SET status='REVOKED' WHERE id=$1",[card]);assert.equal((await send(event())).body.outcome,'CARD_NOT_ACTIVE');await pool.query("UPDATE student_cards SET status='ACTIVE',expires_at=now()-interval '1 second' WHERE id=$1",[card]);assert.equal((await send(event())).body.outcome,'CARD_NOT_ACTIVE');});
test('outside roster rejected',async()=>{await pool.query('DELETE FROM session_roster');assert.equal((await send(event())).body.outcome,'NOT_IN_ROSTER');});
test('closed session rejects new event but old ACK survives',async()=>{const b=event(),first=await send(b);await pool.query("UPDATE class_sessions SET status='CLOSED'");assert.deepEqual(await send(b),first);assert.equal((await send(event())).body.outcome,'SESSION_NOT_OPEN');});
test('wrong device credential and spoofed device rejected',async()=>{assert.equal((await send(event(),'x'.repeat(40))).status,401);assert.equal((await send({...event(),device_id:device})).status,400);assert.equal(await count('device_events'),0);});
test('malformed and oversized bodies rejected',async()=>{assert.equal((await send({...event(),card_uid:'BAD'})).status,400);assert.equal((await send({...event(),padding:'a'.repeat(9000)})).status,413);});
test('readiness requires migration marker',async()=>{await pool.query("DELETE FROM schema_migrations WHERE version='001'");try{assert.equal((await fetch(base+'/readyz')).status,503);}finally{await pool.query("INSERT INTO schema_migrations VALUES('001')");}});
test('active card unique and student account nonnegative',async()=>{await assert.rejects(pool.query("INSERT INTO student_cards(id,student_id,uid_hmac,status) VALUES($1,$2,$3,'ACTIVE')",[randomUUID(),outsider,cardHash('DEADBEEF',key)]));await assert.rejects(pool.query("INSERT INTO ledger_accounts VALUES($1,'STUDENT',-1)",[randomUUID()]));});
test('ledger rejects unbalanced transaction, seals balanced posting',async()=>{
 const a=randomUUID(),b=randomUUID(),w=randomUUID(),request=randomUUID(),tx=randomUUID();
 await pool.query("INSERT INTO ledger_accounts VALUES($1,'STUDENT',0),($2,'SIM_SOURCE',0)",[a,b]);
 await pool.query('INSERT INTO wallets VALUES($1,$2,$3)',[w,student,a]);await pool.query('INSERT INTO topup_requests(id,wallet_id,amount) VALUES($1,$2,100)',[request,w]);
 const c=await pool.connect();try{
 await c.query('BEGIN');await c.query("INSERT INTO ledger_transactions(id,kind,topup_id) VALUES($1,'TOPUP',$2)",[tx,request]);await assert.rejects(c.query('COMMIT'));await c.query('ROLLBACK');
 await c.query('BEGIN');await c.query("INSERT INTO ledger_transactions(id,kind,topup_id) VALUES($1,'TOPUP',$2)",[tx,request]);
 await c.query('INSERT INTO ledger_entries VALUES($1,$2,$3,100),($4,$2,$5,-100)',[randomUUID(),tx,a,randomUUID(),b]);await c.query('COMMIT');
 await assert.rejects(c.query('UPDATE ledger_entries SET delta=1 WHERE transaction_id=$1',[tx]));
 const other=randomUUID();await c.query("INSERT INTO ledger_accounts VALUES($1,'STUDENT',0)",[other]);
 await assert.rejects(c.query('INSERT INTO ledger_entries VALUES($1,$2,$3,1)',[randomUUID(),tx,other]),/Entries must be created with header/);
 }finally{await c.query('ROLLBACK');c.release();}
});
test('database failure rolls back event and clean retry succeeds',async()=>{
 await pool.query(`CREATE FUNCTION test_failure() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN RAISE EXCEPTION 'injected'; END $$; CREATE TRIGGER fail_attendance BEFORE INSERT ON attendance_records FOR EACH ROW EXECUTE FUNCTION test_failure()`);
 const b=event();try{assert.equal((await send(b)).status,503);assert.equal(await count('device_events'),0);assert.equal(await count('attendance_records'),0);}finally{await pool.query('DROP TRIGGER fail_attendance ON attendance_records; DROP FUNCTION test_failure()');}
 assert.equal((await send(b)).status,201);
});
