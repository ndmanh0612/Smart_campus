from pathlib import Path
import hashlib,json,math
import cv2
import numpy as np
ROOT=Path(__file__).resolve().parents[1]/'models'
def percentile(values,p):
 if not values or not 0<p<=100:raise ValueError('Nonempty timings, percentile in (0,100]')
 return sorted(values)[math.ceil(len(values)*p/100)-1]
def state():return {'verified':False,'reason':'PAD_NOT_CONFIGURED','threshold':'NOT_CALIBRATED'}
def checked_model(spec):
 path=ROOT/spec['file']
 if hashlib.sha256(path.read_bytes()).hexdigest()!=spec['sha256']:
  raise ValueError('Model checksum mismatch')
 return str(path)

def create_face_detector(spec):
 return cv2.FaceDetectorYN.create(checked_model(spec),'',(640,480),.9,.3,5000)

class Runtime:
 def __init__(self):
  m=json.loads((ROOT/'manifest.json').read_text())
  cv2.setNumThreads(1)
  self.detector=create_face_detector(m['yunet'])
  self.recognizer=cv2.FaceRecognizerSF.create(checked_model(m['sface']),'')
 def blank(self):return self.detector.detect(np.zeros((480,640,3),dtype=np.uint8))[1]
 def synthetic(self):return self.recognizer.feature(np.zeros((112,112,3),dtype=np.uint8))
