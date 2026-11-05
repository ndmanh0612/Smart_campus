from pathlib import Path
import json,hashlib,urllib.request,re
from concurrent.futures import ThreadPoolExecutor
ROOT=Path(__file__).resolve().parents[1]
REPO='ndmanh0612/tapcard-iotproject'
COMMIT='6f600226e3f0f383897ee5d2d607733e5a80c84f'
def read(url):
 with urllib.request.urlopen(urllib.request.Request(url,headers={'User-Agent':'smartcard-source-review'}),timeout=60) as r:return r.read()
def main():
 commit=COMMIT
 tree=json.loads(read(f'https://api.github.com/repos/{REPO}/git/trees/{commit}?recursive=1'))
 paths=[x['path'] for x in tree['tree'] if x['type']=='blob']
 out=ROOT/'.work/tapcard-reference';out.mkdir(parents=True,exist_ok=True)
 (out/'tree.json').write_text(json.dumps(paths,indent=2))
 wanted=[p for p in paths if p in ['README.md','LICENSE','LICENSE.md','express/package.json','flutter/pubspec.yaml','arduino/arduino.ino','flutter/android/app/build.gradle.kts','flutter/android/app/src/main/AndroidManifest.xml'] or (p.startswith(('express/src/','flutter/lib/')) and p.endswith(('.ts','.dart')))]
 def fetch(p):
  url=f'https://raw.githubusercontent.com/{REPO}/{commit}/{p}';raw=read(url);lines=[]
  for line in raw.decode('utf-8-sig').splitlines():
   if re.search(r'(password|ssid|secret|api_?key|jwt|atlas|aes_key|\bkey\b|\biv\b)',line,re.I):
    line=re.sub(r'([=:]\s*)[\"\'][^\"\']*[\"\']',r'\1"<redacted-literal>"',line)
   lines.append(line)
  target=out/p;target.parent.mkdir(parents=True,exist_ok=True);target.write_text('\n'.join(lines),encoding='utf-8')
  return {'path':p,'source':url,'sha256_original':hashlib.sha256(raw).hexdigest(),'inspection_copy_sanitized':True}
 with ThreadPoolExecutor(max_workers=5) as e:files=list(e.map(fetch,wanted))
 manifest={'repository':REPO,'commit':commit,'files':files,'note':'No .env downloaded. Application source inspection only; no runtime verified.'}
 evidence=ROOT/'docs/evidence';evidence.mkdir(parents=True,exist_ok=True)
 (evidence/'tapcard-source.json').write_text(json.dumps(manifest,indent=2),encoding='utf-8')
 print(json.dumps({'commit':commit,'files':len(files),'paths':wanted},indent=2))
if __name__=='__main__':main()
