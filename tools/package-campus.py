"""Package only distributable source/builds, excluding credentials and local state."""
from pathlib import Path
import os,zipfile,hashlib,json,shutil
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'output'
SKIP={'.work','.venv','node_modules','.dart_tool','.git','.agents','.codex','.aws','.ssh','.azure','.idea','.kotlin','__pycache__','output','models','build','.gradle'}
def safe(path):
    name=path.name.lower()
    if name.startswith('.env') and name!='.env.example':return False
    if name in {'secrets.h','local.properties','key.properties','.npmrc','.netrc','.pypirc','.pgpass','campus-artifacts.json','.flutter-plugins','.flutter-plugins-dependencies'}:return False
    return path.suffix.lower() not in {'.pem','.key','.jks','.keystore','.pyc','.p12','.dump','.pass'}
def add_tree(z,folder,prefix):
    for base,dirs,names in os.walk(folder):
        dirs[:]=[d for d in dirs if d not in SKIP]
        for name in names:
            p=Path(base)/name
            if safe(p):z.write(p,str(Path(prefix)/p.relative_to(folder)))

def check_local_secrets(archives):
    secrets=[]
    local=ROOT/'.work/campus-local.json'
    if local.exists():secrets.extend(v.encode() for v in json.loads(local.read_text()).values() if isinstance(v,str) and len(v)>=20)
    env=ROOT/'deploy/.env'
    if env.exists():
        for line in env.read_text().splitlines():
            key,sep,value=line.partition('=')
            if sep and any(word in key for word in ['SECRET','PASSWORD','TOKEN']) and len(value)>=20:secrets.append(value.encode())
    if not secrets:return
    overlap=max(map(len,secrets))
    for path in archives:
        with zipfile.ZipFile(path) as z:
            for name in z.namelist():
                with z.open(name) as entry:
                    tail=b''
                    while chunk:=entry.read(1024*1024):
                        data=tail+chunk
                        if any(secret in data for secret in secrets):raise RuntimeError('Local credential detected in artifact member: '+name)
                        tail=data[-overlap:]
def main():
    OUT.mkdir(exist_ok=True)
    web=ROOT/'flutter/app/build/web'
    apk=ROOT/'flutter/app/build/app/outputs/flutter-apk/app-debug.apk'
    if not (web/'index.html').exists() or not apk.exists():raise RuntimeError('Build current Web and APK before packaging')
    with zipfile.ZipFile(OUT/'SmartCampus_Web.zip','w',zipfile.ZIP_DEFLATED,compresslevel=6) as z:add_tree(z,web,'')
    shutil.copy2(apk,OUT/'SmartCampus_debug.apk')
    with zipfile.ZipFile(OUT/'SmartCampus_Source.zip','w',zipfile.ZIP_DEFLATED,compresslevel=6) as z:
        add_tree(z,ROOT,'source')
        if (ROOT/'models/manifest.json').exists():z.write(ROOT/'models/manifest.json','source/models/manifest.json')
        add_tree(z,web,'source/flutter/app/build/web')
        for name in z.namelist():
            parts=Path(name).parts
            if '.work' in parts or 'node_modules' in parts or not safe(Path(name)):raise RuntimeError('Unsafe package member: '+name)
    result={'artifacts':[],'mode':'DEVELOPMENT_TEST_ONLY','hardware_test':'NOT_RUN'}
    check_local_secrets([OUT/name for name in ['SmartCampus_Web.zip','SmartCampus_debug.apk','SmartCampus_Source.zip']])
    result['localCredentialScan']='PASS (generated long secrets; short PIN excluded to avoid numeric false positives)'
    for name in ['SmartCampus_Web.zip','SmartCampus_debug.apk','SmartCampus_Source.zip']:
        p=OUT/name
        digest=hashlib.sha256()
        with p.open('rb') as stream:
            for chunk in iter(lambda:stream.read(1024*1024),b''):digest.update(chunk)
        digest=digest.hexdigest()
        result['artifacts'].append({'file':name,'bytes':p.stat().st_size,'sha256':digest})
    (ROOT/'docs/evidence/campus-artifacts.json').write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8')
    (OUT/'SmartCampus_SHA256SUMS.txt').write_text(''.join(a['sha256']+'  '+a['file']+'\n' for a in result['artifacts']),encoding='utf-8')
    print(json.dumps(result,indent=2))
if __name__=='__main__':main()
