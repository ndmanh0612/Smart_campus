import express, {type ErrorRequestHandler} from 'express';
import {createHash,createHmac,randomUUID} from 'node:crypto';
import type {Pool} from 'pg';
export const digest=(s:string)=>createHash('sha256').update(s).digest('hex');
export const cardHash=(uid:string,key:string)=>createHmac('sha256',key).update(uid.toUpperCase()).digest('hex');
const uuid=/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
export function createApp(pool:Pool,key:string){
  if(key.length<32)throw Error('CARD_HMAC_SECRET requires at least 32 characters');
  const app=express();app.disable('x-powered-by');
  app.use((_req,res,next)=>{res.set('X-Request-Id',randomUUID());res.set('Cache-Control','no-store');next();});
  app.use(express.json({limit:'8kb'}));
  app.get('/healthz',(_req,res)=>res.json({status:'ok',mode:'week1-prototype'}));
  app.get('/readyz',async(_req,res,next)=>{
    try{const r=await pool.query("SELECT version FROM schema_migrations WHERE version='001'");
      res.status(r.rowCount===1?200:503).json({ready:r.rowCount===1});}catch(e){next(e);}
  });
  app.post('/v1/device-events',async(req,res,next)=>{
    const token=req.get('Authorization')??'';
    if(!/^Bearer [A-Za-z0-9_-]{32,256}$/.test(token)){res.status(401).json({code:'DEVICE_UNAUTHORIZED'});return;}
    const b=req.body;
    if(!b||Array.isArray(b)||Object.keys(b).some(k=>!['event_id','card_uid','purpose'].includes(k))||
      typeof b.event_id!=='string'||!uuid.test(b.event_id)||typeof b.card_uid!=='string'||
      !/^(?:[a-f0-9]{8}|[a-f0-9]{14}|[a-f0-9]{20})$/i.test(b.card_uid)||b.purpose!=='ATTENDANCE'){
      res.status(400).json({code:'INVALID_EVENT'});return;}
    const input={event_id:b.event_id.toLowerCase(),card_uid:b.card_uid.toUpperCase(),purpose:'ATTENDANCE'};
    const hash=digest(JSON.stringify(input));let c;
    try{
      c=await pool.connect();await c.query('BEGIN');
      await c.query("SET LOCAL lock_timeout='5s'; SET LOCAL statement_timeout='8s'");
      const device=(await c.query('SELECT id FROM devices WHERE token_hash=$1 AND active FOR UPDATE',[digest(token.slice(7))])).rows[0];
      if(!device){await c.query('ROLLBACK');res.status(401).json({code:'DEVICE_UNAUTHORIZED'});return;}
      const prior=(await c.query('SELECT payload_hash,http_status,response FROM device_events WHERE device_id=$1 AND event_id=$2',[device.id,input.event_id])).rows[0];
      if(prior){await c.query('COMMIT');res.status(prior.payload_hash===hash?prior.http_status:409).json(prior.payload_hash===hash?prior.response:{code:'IDEMPOTENCY_CONFLICT'});return;}
      await c.query('INSERT INTO device_events(device_id,event_id,payload_hash) VALUES($1,$2,$3)',[device.id,input.event_id,hash]);
      const finish=async(status:number,body:Record<string,unknown>)=>{
        await c!.query('UPDATE device_events SET http_status=$3,response=$4 WHERE device_id=$1 AND event_id=$2',[device.id,input.event_id,status,body]);
        await c!.query('COMMIT');res.status(status).json(body);
      };
      const base={event_id:input.event_id};
      const session=(await c.query(`SELECT s.id,s.late_after FROM class_sessions s JOIN session_devices d ON d.session_id=s.id
        WHERE d.device_id=$1 AND d.released_at IS NULL AND s.status='OPEN' FOR UPDATE OF s`,[device.id])).rows[0];
      if(!session){await finish(422,{...base,outcome:'SESSION_NOT_OPEN'});return;}
      const student=(await c.query(`SELECT s.id FROM students s JOIN student_cards t ON t.student_id=s.id
        WHERE t.uid_hmac=$1 AND t.status='ACTIVE' AND s.active AND (t.expires_at IS NULL OR t.expires_at>now()) FOR SHARE OF s,t`,[cardHash(input.card_uid,key)])).rows[0];
      if(!student){await finish(422,{...base,outcome:'CARD_NOT_ACTIVE'});return;}
      const roster=await c.query('SELECT 1 FROM session_roster WHERE session_id=$1 AND student_id=$2',[session.id,student.id]);
      if(!roster.rowCount){await finish(422,{...base,outcome:'NOT_IN_ROSTER'});return;}
      const inserted=await c.query(`INSERT INTO attendance_records(id,session_id,student_id,method,status)
        VALUES($1,$2,$3,'RFID',CASE WHEN clock_timestamp()>$4 THEN 'LATE' ELSE 'PRESENT' END)
        ON CONFLICT(session_id,student_id) DO NOTHING RETURNING id`,[randomUUID(),session.id,student.id,session.late_after]);
      const record=(await c.query('SELECT id,status FROM attendance_records WHERE session_id=$1 AND student_id=$2',[session.id,student.id])).rows[0];
      await finish(inserted.rowCount?201:200,{...base,outcome:inserted.rowCount?'RECORDED':'ALREADY_RECORDED',attendance_id:record.id,status:record.status});
    }catch(e){if(c)await c.query('ROLLBACK').catch(()=>{});next(e);}finally{c?.release();}
  });
  app.use((_req,res)=>res.status(404).json({code:'NOT_IMPLEMENTED_IN_WEEK1'}));
  const errors:ErrorRequestHandler=(e,_req,res,_next)=>{
    const code=e?.type==='entity.too.large'?'BODY_TOO_LARGE':e?.type==='entity.parse.failed'?'INVALID_JSON':'DEPENDENCY_UNAVAILABLE';
    res.status(code==='BODY_TOO_LARGE'?413:code==='INVALID_JSON'?400:503).json({code,request_id:res.getHeader('X-Request-Id')});
  };app.use(errors);return app;
}
