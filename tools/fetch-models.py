from pathlib import Path
import hashlib,json,re,urllib.request
ROOT=Path(__file__).resolve().parents[1]
COMMIT='48b10fa505aeb51fbd127fc60a5c660040e823b7'
SPECS=[('yunet','face_detection_yunet','face_detection_yunet_2023mar.onnx','8f2383e4dd3cfbb4553ea8718107fc0423210dc964f9f4280604804ed2552fa4','MIT'),('sface','face_recognition_sface','face_recognition_sface_2021dec.onnx','0ba9fbfa01b5270c96627c4ef784da859931e02f04419c829e83484087c34e79','Apache-2.0')]
def read(url):
 with urllib.request.urlopen(urllib.request.Request(url,headers={'User-Agent':'smartcard-week1'}),timeout=120) as r:return r.read()
def main():
 out=ROOT/'models';out.mkdir(exist_ok=True);license_dir=ROOT/'docs/licenses';license_dir.mkdir(parents=True,exist_ok=True);manifest={}
 for key,folder,name,expected,license_name in SPECS:
  base=f'https://raw.githubusercontent.com/opencv/opencv_zoo/{COMMIT}/models/{folder}/'
  pointer=read(base+name).decode();assert re.search('oid sha256:([0-9a-f]{64})',pointer)[1]==expected
  target=out/name
  content=target.read_bytes() if target.exists() else read(f'https://media.githubusercontent.com/media/opencv/opencv_zoo/{COMMIT}/models/{folder}/{name}')
  assert hashlib.sha256(content).hexdigest()==expected
  target.write_bytes(content);notice=read(base+'LICENSE');(license_dir/f'{key}-LICENSE.txt').write_bytes(notice)
  manifest[key]={'file':name,'sha256':expected,'license':license_name,'license_url':base+'LICENSE','commit':COMMIT}
 manifest['pad']={'status':'NOT_SELECTED','verified_allowed':False}
 (out/'manifest.json').write_text(json.dumps(manifest,indent=2),encoding='utf-8');print('Two model hashes verified; PAD unavailable')
if __name__=='__main__':main()
