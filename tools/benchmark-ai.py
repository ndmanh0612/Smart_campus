from pathlib import Path
import sys,time,json,platform
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'ai-service'))
from runtime import Runtime,percentile,state
root=Path(__file__).resolve().parents[1]
start=time.perf_counter();runtime=Runtime();cold=(time.perf_counter()-start)*1000
for _ in range(5):runtime.blank();runtime.synthetic()
detector=[];embedding=[]
for _ in range(100):
 start=time.perf_counter();runtime.blank();detector.append((time.perf_counter()-start)*1000)
 start=time.perf_counter();runtime.synthetic();embedding.append((time.perf_counter()-start)*1000)
report={'kind':'SYNTHETIC_RUNTIME_ONLY','python':platform.python_version(),'runs':100,'warmup':5,'cold_load_ms':cold,'detector_blank_ms':{'p50':percentile(detector,50),'p95':percentile(detector,95)},'embedding_synthetic_ms':{'p50':percentile(embedding,50),'p95':percentile(embedding,95)},'authorization':state(),'limitations':['No real faces, no alignment/PAD/accuracy','Not 20 clients for 10 minutes','Not a VPS benchmark; do not add component P95 into end-to-end P95']}
(root/'docs/evidence/ai-benchmark.json').write_text(json.dumps(report,indent=2));print(json.dumps(report,indent=2))
