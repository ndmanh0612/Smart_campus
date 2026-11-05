import os,secrets
from contextlib import asynccontextmanager
from fastapi import FastAPI,Header,HTTPException
from fastapi.responses import JSONResponse
from runtime import Runtime,state
@asynccontextmanager
async def lifespan(app):
 if len(os.environ.get('AI_SERVICE_TOKEN',''))<32:raise RuntimeError('AI_SERVICE_TOKEN required')
 app.state.runtime=Runtime();yield
app=FastAPI(lifespan=lifespan,docs_url=None,redoc_url=None,openapi_url=None)
def auth(value):
 if not secrets.compare_digest(value or '', 'Bearer '+os.environ.get('AI_SERVICE_TOKEN','')):raise HTTPException(401,'Unauthorized')
@app.get('/healthz')
def health():return {'status':'ok'}
@app.get('/readyz')
def ready(authorization:str|None=Header(default=None)):
 auth(authorization);return JSONResponse(state(),status_code=503)
@app.post('/internal/face/verify')
def verify(authorization:str|None=Header(default=None)):
 auth(authorization);return JSONResponse(state(),status_code=503)
