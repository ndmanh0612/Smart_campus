// Software-only smoke through the local Compose reverse proxy. Never simulates RFID scans.
import assert from 'node:assert/strict';
import {readFile,writeFile} from 'node:fs/promises';
import {randomUUID} from 'node:crypto';
import {fixtureId as fid} from '../backend/src/database.ts';
const root=new URL('../',import.meta.url);
const env=Object.fromEntries((await readFile(new URL('deploy/.env',root),'utf8')).split(/\r?\n/).filter(s=>s&&!s.startsWith('#')).map(s=>{const at=s.indexOf('=');return [s.slice(0,at),s.slice(at+1)];}));
assert.equal(env.DEPLOY_ENV,'campus-local','Only the dedicated local demo deployment is supported');
const base='http://localhost:8080',evidence=new URL('docs/evidence/compose-smoke.json',root);
async function api(path,{method='GET',body,token='',key=randomUUID(),status}={}){
 const response=await fetch(base+'/api/v1'+path,{method,headers:{'Content-Type':'application/json','X-Client-Type':'native','Idempotency-Key':key,...(token?{Authorization:'Bearer '+token}:{})},body:body===undefined?undefined:JSON.stringify(body),signal:AbortSignal.timeout(30000)});
 const parsed=await response.json();if(status===undefined)assert.ok(response.ok,`${path}: ${parsed.error?.code??response.status}`);else assert.equal(response.status,status,`${path}: ${parsed.error?.code??response.status}`);return parsed.data;
}
async function login(name){return (await api('/auth/login',{method:'POST',body:{email:name+'@campus.test',password:env.SEED_PASSWORD}})).accessToken;}
for(const path of ['/healthz','/readyz','/']){const response=await fetch(base+path);assert.equal(response.status,200,path);if(path==='/')assert.match(await response.text(),/flutter_bootstrap/);}
for(const [path,type] of [['/flutter_bootstrap.js','javascript'],['/canvaskit/canvaskit.wasm','wasm'],['/assets/assets/fonts/roboto-regular.ttf','font']]){const response=await fetch(base+path,{method:'HEAD'});assert.equal(response.status,200,path);assert.ok(response.headers.get('content-type')?.includes(type),path);}
assert.equal((await fetch(base+'/api/v1/internal/mock-payment-callbacks',{method:'POST'})).status,404);
const admin=await login('admin'),student=await login('student');
const get=(p,token=admin)=>api(p,{token});
const post=(p,body,token=admin,key)=>api(p,{method:'POST',body,token,key});
const wallet=()=>get('/me/wallet',student);
if(process.argv.includes('--verify-restart')){
 const expected=JSON.parse(await readFile(evidence,'utf8'));
 assert.equal((await wallet()).postedPoints,expected.postedPoints);
 assert.equal((await get('/canteen/orders/'+expected.orderId)).status,'COMPLETED');
 assert.equal((await get('/parking/sessions/'+expected.parkingSessionId)).status,'COMPLETED');
 assert.deepEqual(await get('/admin/wallet-reconciliation'),[]);
 expected.restart={status:'PASS',checkedAt:new Date().toISOString()};
 await writeFile(evidence,JSON.stringify(expected,null,2)+'\n');
 console.log('Compose restart: PASS; wallet and completed orders/parking preserved.');
 process.exit(0);
}
await api('/admin/users',{token:student,status:403});
const before=BigInt((await wallet()).postedPoints),key=randomUUID();
const topup=await post('/me/topups',{requestedVnd:'50000'},student,key);
assert.equal((await post('/me/topups',{requestedVnd:'50000'},student,key)).id,topup.id);
const deadline=Date.now()+120000;
while((await get('/me/topups/'+topup.id,student)).status!=='SUCCEEDED'){
 assert.ok(Date.now()<deadline,'MOCK worker top-up timed out');await new Promise(r=>setTimeout(r,500));
}
assert.equal((await wallet()).postedPoints,(before+50000n).toString());
async function face(contextId){return post('/simulator/face-events',{contextId,studentFixtureId:fid('student'),scenario:'SUCCESS'});}
async function approve(paymentId,expectedSourceVersion){return post(`/me/payments/${paymentId}/approvals`,{pin:env.SEED_PIN,expectedSourceVersion},student);}
async function passage(commandId){
 const deadline=Date.now()+90000;
 while((await get('/parking/gate-commands')).find(c=>c.id===commandId)?.status!=='OPENED'){
  assert.ok(Date.now()<deadline,'Gate simulator worker did not open the command');await new Promise(r=>setTimeout(r,300));
 }
 await post('/simulator/gate-scenarios',{commandId,scenario:'PASSAGE',providerEventId:randomUUID()});
}
const order=await post('/canteen/orders',{items:[{productId:fid('DEMO-01'),quantity:1}]});
const pos=await post(`/canteen/orders/${order.id}/checkout-contexts`,{deviceId:fid('demo-pos'),expectedVersion:order.version});
const identity=await face(pos.id);
const identified=await post(`/canteen/orders/${order.id}/identify`,{identityAssertionId:identity.identityAssertionId});
const approval=await approve(identified.paymentId,order.version),captureKey=randomUUID();
const payment={paymentId:identified.paymentId,approvalId:approval.approvalId,expectedVersion:order.version};
await post(`/canteen/orders/${order.id}/payments`,payment,admin,captureKey);
await post(`/canteen/orders/${order.id}/payments`,payment,admin,captureKey);
assert.equal((await get('/canteen/orders/'+order.id)).status,'COMPLETED');
const entryContext=await post('/parking/entry-contexts',{lotId:fid('lot'),deviceId:fid('demo-entry')});
const entryIdentity=await face(entryContext.id);
const ocr=await post('/simulator/ocr-observations',{contextId:entryContext.id,rawText:'59A112345',scenario:'SUCCESS'});
const entry=await post('/parking/entries',{identityAssertionId:entryIdentity.identityAssertionId,ocrObservationId:ocr.id});
await passage(entry.commandId);
const session=await get('/parking/sessions/'+entry.id);
const exitContext=await post(`/parking/sessions/${session.id}/exit-contexts`,{deviceId:fid('demo-exit'),expectedVersion:session.version});
const exitIdentity=await face(exitContext.id);
const exitOcr=await post('/simulator/ocr-observations',{contextId:exitContext.id,rawText:'59A112345',scenario:'SUCCESS'});
const quote=await post(`/parking/sessions/${session.id}/exit-quotes`,{identityAssertionId:exitIdentity.identityAssertionId,ocrObservationId:exitOcr.id,expectedVersion:session.version});
assert.equal(quote.amountPoints,'3000');
const exitApproval=await approve(quote.paymentId,session.version);
const exit=await post(`/parking/sessions/${session.id}/exit-authorizations`,{quoteId:quote.quoteId,approvalId:exitApproval.approvalId,expectedVersion:session.version});
await passage(exit.commandId);assert.equal((await get('/parking/sessions/'+session.id)).status,'COMPLETED');
const lecturer=await login('lecturer');
const classes=await get('/lecturer/class-sections',lecturer);
const attendance=await post('/attendance/sessions',{scheduleId:classes[0].scheduleId,deviceId:fid('camera')},lecturer);
const opened=await post(`/attendance/sessions/${attendance.id}/open`,{expectedVersion:attendance.version},lecturer);
await post('/simulator/attendance-events',{sessionId:attendance.id,deviceId:fid('camera'),studentFixtureId:fid('student'),scenario:'SUCCESS'},lecturer);
await post(`/attendance/sessions/${attendance.id}/close`,{expectedVersion:opened.version},lecturer);
const records=await get(`/attendance/sessions/${attendance.id}/records`,lecturer);
assert.equal(records.length,2);assert.ok(records.some(r=>r.status==='ABSENT'));
const expectedPoints=(before+32000n).toString();assert.equal((await wallet()).postedPoints,expectedPoints);
assert.deepEqual(await get('/admin/wallet-reconciliation'),[]);
const result={status:'PASS',checkedAt:new Date().toISOString(),mode:'SOFTWARE_DEMO_ONLY',rfidHardware:'NOT_RUN',topupId:topup.id,orderId:order.id,parkingSessionId:session.id,attendanceSessionId:attendance.id,postedPoints:expectedPoints,restart:{status:'NOT_RUN'},checks:['proxy/static/local-assets','internal route blocked','RBAC','MOCK topup/retry/worker','POS Face DEMO/PIN/capture dedupe','parking Face/OCR DEMO/gate passage/capture','lecturer OPEN/Face DEMO/CLOSE/ABSENT','wallet reconciliation']};
await writeFile(evidence,JSON.stringify(result,null,2)+'\n');
console.log('Compose software smoke PASS. RFID hardware NOT_RUN.');
