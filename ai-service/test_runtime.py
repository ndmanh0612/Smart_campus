import unittest
import numpy as np
from runtime import Runtime,percentile,state
class Tests(unittest.TestCase):
 @classmethod
 def setUpClass(cls):cls.runtime=Runtime()
 def test_blank(self):
  faces=self.runtime.blank();self.assertTrue(faces is None or len(faces)==0)
 def test_embedding(self):
  f=self.runtime.synthetic();self.assertEqual(f.shape,(1,128));self.assertTrue(np.isfinite(f).all())
 def test_fail_closed(self):self.assertFalse(state()['verified'])
 def test_percentile(self):self.assertEqual(percentile(list(range(1,101)),95),95)
 def test_empty(self):
  with self.assertRaises(ValueError):percentile([],95)
if __name__=='__main__':unittest.main(verbosity=2)
