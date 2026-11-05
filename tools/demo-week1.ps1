param([string]$PgBin='C:\Program Files\PostgreSQL\17\bin',[string]$Node='C:\Users\dellcuatri142\.cache\codex-runtimes\codex-primary-runtime\dependencies\node\bin\node.exe')
$ErrorActionPreference='Stop'
$root=(Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$data=Join-Path $root '.work\postgres-demo'
if(!(Test-Path -LiteralPath (Join-Path $data 'PG_VERSION'))){
 & (Join-Path $PgBin 'initdb.exe') -D $data -U week1 --auth=trust --encoding=UTF8 --locale=C
 if($LASTEXITCODE -ne 0){throw 'initdb failed'}
}
$started=$false;$prior=$env:DEMO_DATABASE_URL
try{
 & (Join-Path $PgBin 'pg_ctl.exe') -D $data -l (Join-Path $root '.work\postgres-demo.log') -o '-h 127.0.0.1 -p 54330' -w start
 if($LASTEXITCODE -ne 0){throw 'Cannot start demo cluster, inspect port54330'}
 $started=$true
 $exists=& (Join-Path $PgBin 'psql.exe') -h 127.0.0.1 -p 54330 -U week1 -d postgres -tAc "SELECT 1 FROM pg_database WHERE datname='smartcard_week1_demo'"
 if($exists -ne '1'){& (Join-Path $PgBin 'createdb.exe') -h 127.0.0.1 -p 54330 -U week1 smartcard_week1_demo;if($LASTEXITCODE -ne 0){throw 'createdb failed'}}
 $env:DEMO_DATABASE_URL='postgresql://week1@127.0.0.1:54330/smartcard_week1_demo'
 & $Node (Join-Path $root 'backend\demo.ts')
 if($LASTEXITCODE -ne 0){throw 'Demo failed; inspect evidence/log'}
}finally{
 $env:DEMO_DATABASE_URL=$prior
 if($started){& (Join-Path $PgBin 'pg_ctl.exe') -D $data -w stop}
}
