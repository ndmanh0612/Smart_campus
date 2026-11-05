"""Install an isolated Arduino CLI and verified archive; never changes global PATH."""
from pathlib import Path
import hashlib,json,urllib.request,zipfile,subprocess
ROOT=Path(__file__).resolve().parents[1]
DEST=ROOT/'.work/toolchains/arduino'
def read(url):
    with urllib.request.urlopen(urllib.request.Request(url,headers={'User-Agent':'smartcampus-firmware-build'}),timeout=120) as response:
        return response.read()
def main():
    DEST.mkdir(parents=True,exist_ok=True)
    release=json.loads(read('https://api.github.com/repos/arduino/arduino-cli/releases/tags/v1.5.1'))
    assets=release['assets']
    archive=next(a for a in assets if a['name'].endswith('_Windows_64bit.zip'))
    checksums=next(a for a in assets if a['name'].endswith('checksums.txt'))
    sums=read(checksums['browser_download_url']).decode()
    wanted=next(line.split()[0] for line in sums.splitlines() if line.split()[-1].lstrip('*')==archive['name'])
    if wanted!='fabe42e0eb04d00e776a66178299ff95a46c623dbc260f997e58fd514853dd40':
        raise RuntimeError('Pinned Arduino archive checksum changed')
    path=DEST/archive['name']
    if not path.exists() or hashlib.sha256(path.read_bytes()).hexdigest()!=wanted:
        path.write_bytes(read(archive['browser_download_url']))
    if hashlib.sha256(path.read_bytes()).hexdigest()!=wanted:
        raise RuntimeError('Arduino archive checksum mismatch')
    with zipfile.ZipFile(path) as z:
        for member in z.infolist():
            (DEST/member.filename).resolve().relative_to(DEST.resolve())
        z.extractall(DEST)
    config={'board_manager':{'additional_urls':['https://espressif.github.io/arduino-esp32/package_esp32_index.json']},'directories':{'data':str(DEST/'data'),'downloads':str(DEST/'downloads'),'user':str(DEST/'user')},'updater':{'enable_notification':False}}
    cfg=DEST/'arduino-cli.yaml'
    # JSON is a YAML 1.2 subset accepted by Arduino CLI.
    cfg.write_text(json.dumps(config,indent=2),encoding='utf-8')
    cli=str(DEST/'arduino-cli.exe')
    def run(*args):
        subprocess.run([cli,'--config-file',str(cfg),*args],check=True)
    run('core','update-index')
    esp=json.loads((DEST/'data/package_esp32_index.json').read_text())
    platforms=next(p for p in esp['packages'] if p['name']=='esp32')['platforms']
    core_version=next(p['version'] for p in platforms if p['architecture']=='esp32' and p['version']=='3.3.12')
    run('core','install','esp32:esp32@'+core_version)
    run('lib','update-index')
    index=json.loads((DEST/'data/library_index.json').read_text(encoding='utf-8'))
    selected={}
    for name,library_version in [('MFRC522','1.4.12'),('LiquidCrystal I2C','1.1.2'),('ArduinoJson','7.4.3')]:
        library=next(x for x in index['libraries'] if x['name']==name and x['version']==library_version)
        selected[name]=library['version'];run('lib','install',name+'@'+library['version'])
    evidence={'arduino_cli':release['tag_name'],'archive_url':archive['browser_download_url'],'sha256':wanted,'esp32_core':core_version,'libraries':selected,'reference_fqbn':'esp32:esp32:esp32','hardware_test':'NOT_RUN'}
    (ROOT/'docs/evidence/firmware-toolchain.json').write_text(json.dumps(evidence,indent=2)+'\n',encoding='utf-8')
    print(json.dumps(evidence,indent=2))
if __name__=='__main__':
    main()
