"""Download official Android command tools after the user's explicit license acceptance."""
from pathlib import Path
import urllib.request,hashlib,zipfile,json,time
ROOT=Path(__file__).resolve().parents[1]
URL='https://dl.google.com/android/repository/commandlinetools-win-15859902_latest.zip'
SHA='90ae805d20434428bffcb699c290860f19bb5f66a67e6b330067e3de801fb04a'
def main():
 base=ROOT/'.work/toolchains';base.mkdir(parents=True,exist_ok=True)
 archive=base/'android-command-tools.zip'
 if not archive.exists():
  with urllib.request.urlopen(URL,timeout=90) as response,archive.with_suffix('.part').open('wb') as f:
   total=0;last=time.monotonic()
   while chunk:=response.read(1024*1024):
    f.write(chunk);total+=len(chunk)
    if time.monotonic()-last>20:print(f'Android tools downloaded {total//1048576} MiB',flush=True);last=time.monotonic()
  archive.with_suffix('.part').replace(archive)
 assert hashlib.sha256(archive.read_bytes()).hexdigest()==SHA,'Android tools checksum mismatch'
 target=base/'android-sdk/cmdline-tools/latest'
 target.mkdir(parents=True,exist_ok=True)
 with zipfile.ZipFile(archive) as z:
  for info in z.infolist():
   relative=Path(info.filename).relative_to('cmdline-tools')
   destination=(target/relative).resolve()
   if not destination.is_relative_to(target.resolve()):raise ValueError('Unsafe archive path')
   if info.is_dir():destination.mkdir(parents=True,exist_ok=True)
   else:destination.parent.mkdir(parents=True,exist_ok=True);destination.write_bytes(z.read(info))
 (ROOT/'docs/evidence/android-tools-download.json').write_text(json.dumps({'url':URL,'sha256':SHA,'license_authorized_by_user':True,'installed':str(target),'sdk_platform_packages':'NOT_INSTALLED_YET'},indent=2))
 print('Official Android command-line tools checksum PASS; packages/licenses next',flush=True)
if __name__=='__main__':main()
