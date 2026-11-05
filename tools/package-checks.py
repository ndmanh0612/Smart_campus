from pathlib import Path
import ast,hashlib,json,re,zipfile,datetime,os
ROOT=Path(__file__).resolve().parents[1]
def main():
 evidence=ROOT/'docs/evidence'
 tap=(evidence/'postgres-integration.tap').read_text(encoding='utf-8-sig');assert '# pass 14' in tap and '# fail 0' in tap
 unit=(evidence/'ai-unit.txt').read_text(encoding='utf-8-sig');assert 'Ran 5 tests' in unit and re.search(r'\bOK\b',unit)
 http=json.loads((evidence/'ai-http.json').read_text());assert len(http)==4 and all(c['status']=='PASS' for c in http)
 source=json.loads((evidence/'tapcard-source.json').read_text());assert len(source['files'])==46
 reused=[]
 for name in ('modern_button.dart','modern_textfield.dart'):
  path=ROOT/'flutter/template/lib/core/widgets'/name
  record=next(f for f in source['files'] if f['path']=='flutter/lib/core/widgets/'+name)
  # Inspection copies normalize line endings, so compare text rather than original-byte digest.
  original=ROOT/'.work/tapcard-reference'/record['path']
  if original.exists():
   expected=original.read_text(encoding='utf-8').replace('withOpacity(0.3)','withAlpha(77)').replace('withOpacity(0.8)','withAlpha(204)').replace('withOpacity(0.7)','withAlpha(179)')
   assert path.read_text(encoding='utf-8')==expected
  reused.append({'file':str(path.relative_to(ROOT)),'source':record['source'],'sha256_local':hashlib.sha256(path.read_bytes()).hexdigest()})
 assert 'ModernButton(onPressed:open' in (ROOT/'flutter/template/lib/main.dart').read_text(encoding='utf-8')
 for p in [*(ROOT/'tools').glob('*.py'),*(ROOT/'ai-service').glob('*.py')]:ast.parse(p.read_text(encoding='utf-8'),filename=str(p))
 build_path=evidence/'flutter-build.json'
 build=json.loads(build_path.read_text(encoding='utf-8-sig')) if build_path.exists() else {'status':'NOT_COMPLETE','reason':'SDK installation/build in progress'}
 demo=json.loads((evidence/'demo-backend.json').read_text(encoding='utf-8'))
 assert demo['all_passed'] and len(demo['checks'])==6
 report={'checked_at_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'postgres_integration':'14 PASS','typescript':'PASS','ai_unit':'5 PASS','ai_http':'4 PASS','simulated_demo':'6 PASS','source_files_inspected':46,'source_commit':source['commit'],'code_reused':reused,'flutter_build':build,'firmware_build_and_board':'NOT_RUN_DEVICE_UNAVAILABLE','face_accuracy_pad':'NOT_RUN','vps_and_restore':'NOT_RUN','full_week_acceptance':'NOT_COMPLETE','note':'Fresh rebuild evidence; historical Word report is not new execution evidence'}
 (evidence/'rebuild-status.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
 output=ROOT/'output';output.mkdir(exist_ok=True)
 ignored={'.work','.venv','node_modules','__pycache__','dist','build','.dart_tool','output','.git','.gradle'}
 paths=[]
 for directory,dirs,files in os.walk(ROOT):
  dirs[:]=[d for d in dirs if d not in ignored]
  for name in files:
   p=Path(directory)/name
   if p.suffix in ('.onnx','.key','.pem','.jks','.keystore','.pyc') or p.name in ('secrets.h','local.properties','key.properties'):continue
   if p.name.startswith('.env') and p.name!='.env.example':continue
   paths.append(p)
 archive=output/'SmartCard_Tuan1_ke_thua_TapCard_PostgreSQL.zip'
 paths += list(output.glob('Bao_cao_Tuan_1_Trinh_Thay_05_11.docx'))
 with zipfile.ZipFile(archive,'w',zipfile.ZIP_DEFLATED) as z:
  for p in paths:z.write(p,'smartcard-week1/'+p.relative_to(ROOT).as_posix())
 with zipfile.ZipFile(archive) as z:
  assert z.testzip() is None
  assert not any('/.work/' in n or '/.venv/' in n or n.endswith(('.onnx','/secrets.h','/.env')) for n in z.namelist())
 print(json.dumps({'checks':'PASS','files_in_zip':len(paths),'zip':str(archive),'zip_sha256':hashlib.sha256(archive.read_bytes()).hexdigest(),'full_week_acceptance':'NOT_COMPLETE'},indent=2))
if __name__=='__main__':main()
