from pathlib import Path
import hashlib,json,math
import cv2
import numpy as np
ROOT=Path(__file__).resolve().parents[1]/'models'
def percentile(values,p):
 if not values or not 0<p<=100:raise ValueError('Nonempty timings, percentile in (0,100]')
 return sorted(values)[math.ceil(len(values)*p/100)-1]
def state():return {'verified':False,'reason':'PAD_NOT_CONFIGURED','threshold':'NOT_CALIBRATED'}
class Runtime:
 def __init__(self):
  m=json.loads((ROOT/'manifest.json').read_text())
  for k in ('yunet','sface'):
   if hashlib.sha256((ROOT/m[k]['file']).read_bytes()).hexdigest()!=m[k]['sha256']:raise ValueError('Model checksum mismatch')
  cv2.setNumThreads(1)
  self.detector=cv2.FaceDetectorYN.create(str(ROOT/m['yunet']['file']),'',(640,480),.9,.3,5000)
  self.recognizer=cv2.FaceRecognizerSF.create(str(ROOT/m['sface']['file']),'')
 def blank(self):return self.detector.detect(np.zeros((480,640,3),dtype=np.uint8))[1]
 def synthetic(self):return self.recognizer.feature(np.zeros((112,112,3),dtype=np.uint8))
