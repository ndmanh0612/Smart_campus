from pathlib import Path
import json,os,secrets,socket,subprocess,sys,time,urllib.request,urllib.error
ROOT=Path(__file__).resolve().parents[1]
with socket.socket() as s:s.bind(('127.0.0.1',0));port=s.getsockname()[1]
token=secrets.token_hex(32)
def request(path,authorized=False,method='GET'):
 req=urllib.request.Request(f'http://127.0.0.1:{port}'+path,method=method,headers={'Authorization':'Bearer '+token} if authorized else {})
 try:
  with urllib.request.urlopen(req,timeout=5) as r:return r.status,json.load(r)
 except urllib.error.HTTPError as e:return e.code,json.load(e)
def main():
 evidence=ROOT/'docs/evidence';evidence.mkdir(parents=True,exist_ok=True)
 with (ROOT/'.work/ai.log').open('w') as log:
  p=subprocess.Popen([sys.executable,'-m','uvicorn','app:app','--host','127.0.0.1','--port',str(port)],cwd=ROOT/'ai-service',env={**os.environ,'AI_SERVICE_TOKEN':token},stdout=log,stderr=log)
  try:
   deadline=time.monotonic()+45
   while True:
    if p.poll() is not None:raise RuntimeError('AI startup failed; inspect .work/ai.log')
    try:
     if request('/healthz')[0]==200:break
    except OSError:pass
    if time.monotonic()>deadline:raise TimeoutError('Startup timeout')
    time.sleep(.2)
   checks=[]
   for path,auth,method,expected in [('/healthz',False,'GET',200),('/readyz',False,'GET',401),('/readyz',True,'GET',503),('/internal/face/verify',True,'POST',503)]:
    actual,body=request(path,auth,method);assert actual==expected
    if auth:assert body['verified'] is False
    checks.append({'path':path,'expected':expected,'actual':actual,'status':'PASS'})
   (evidence/'ai-http.json').write_text(json.dumps(checks,indent=2));print('4 HTTP checks PASS; no Face authorization')
  finally:
   p.terminate()
   try:p.wait(timeout=8)
   except subprocess.TimeoutExpired:p.kill();p.wait()
if __name__=='__main__':main()
