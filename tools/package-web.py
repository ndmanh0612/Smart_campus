from pathlib import Path
import zipfile,hashlib,json
ROOT=Path(__file__).resolve().parents[1]
def main():
 web=ROOT/'flutter/app/build/web';out=ROOT/'output/SmartCard_Web_Tuan1.zip'
 assert (web/'index.html').exists() and (web/'main.dart.js').exists()
 files=[p for p in web.rglob('*') if p.is_file()]
 with zipfile.ZipFile(out,'w',zipfile.ZIP_DEFLATED) as z:
  for p in files:z.write(p,p.relative_to(web).as_posix())
 with zipfile.ZipFile(out) as z:
  assert z.testzip() is None and 'index.html' in z.namelist()
 report={'file':out.name,'files':len(files),'bytes':out.stat().st_size,'sha256':hashlib.sha256(out.read_bytes()).hexdigest(),'scope':'Flutter Web camera spike; build artifact, not real camera test'}
 (ROOT/'docs/evidence/web-artifact.json').write_text(json.dumps(report,indent=2));print(json.dumps(report,indent=2))
if __name__=='__main__':main()
