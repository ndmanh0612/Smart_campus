from pathlib import Path
import sys,json,urllib.request,hashlib
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'.work/config-validator'))
import yaml
import jsonschema
def read(url):
 with urllib.request.urlopen(urllib.request.Request(url,headers={'User-Agent':'smartcard-compose-check'}),timeout=60) as r:return r.read()
def main():
 meta=json.loads(read('https://api.github.com/repos/compose-spec/compose-spec/commits/main'))
 commit=meta['sha'];url=f'https://raw.githubusercontent.com/compose-spec/compose-spec/{commit}/schema/compose-spec.json'
 raw=read(url);schema=json.loads(raw)
 config=yaml.safe_load((ROOT/'deploy/compose.yaml').read_text(encoding='utf-8'))
 jsonschema.validate(config,schema)
 for name in ('db','ai'):
  assert 'ports' not in config['services'][name]
  assert config['services'][name]['networks']==['private']
 assert config['networks']['private']['internal'] is True
 record={'validation':'PASS','schema_url':url,'schema_sha256':hashlib.sha256(raw).hexdigest(),'compose_file_sha256':hashlib.sha256((ROOT/'deploy/compose.yaml').read_bytes()).hexdigest(),'checks':['Compose Specification JSON schema','No published DB/AI ports','Private internal network'],'docker_config_or_build':'NOT_RUN_DOCKER_NOT_INSTALLED','vps_deployment':'NOT_RUN'}
 (ROOT/'docs/evidence/compose-schema.json').write_text(json.dumps(record,indent=2));print(json.dumps(record,indent=2))
if __name__=='__main__':main()
