param([string]$PgBin='',[string]$Node='')
$ErrorActionPreference='Stop'
$root=(Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
if (!$PgBin) {
    if (Test-Path 'C:\Program Files\PostgreSQL\17\bin\pg_ctl.exe') { $PgBin = 'C:\Program Files\PostgreSQL\17\bin' }
    elseif (Test-Path (Join-Path $root '.work\pg\package\native\bin\pg_ctl.exe')) { $PgBin = Join-Path $root '.work\pg\package\native\bin' }
}
if (!$Node) {
    $found = (Get-Command node -ErrorAction SilentlyContinue)
    if ($found) { $Node = $found.Source }
    elseif (Test-Path 'C:\Program Files\nodejs\node.exe') { $Node = 'C:\Program Files\nodejs\node.exe' }
}
$data=Join-Path $root '.work\postgres-rebuild'
$evidence=Join-Path $root 'docs\evidence'
New-Item -ItemType Directory -Force -Path $evidence | Out-Null
if(!(Test-Path -LiteralPath (Join-Path $data 'PG_VERSION'))){
 & (Join-Path $PgBin 'initdb.exe') -D $data -U week1 --auth=trust --encoding=UTF8 --locale=C
 if($LASTEXITCODE -ne 0){throw 'initdb failed'}
}
$started=$false
$prior=$env:TEST_DATABASE_URL
try{
 & (Join-Path $PgBin 'pg_ctl.exe') -D $data -l (Join-Path $root '.work\postgres.log') -o '-h 127.0.0.1 -p 54329' -w start
 if($LASTEXITCODE -ne 0){throw 'Cannot start dedicated test cluster; inspect port ownership'}
 $started=$true
 $exists=& (Join-Path $PgBin 'psql.exe') -h 127.0.0.1 -p 54329 -U week1 -d postgres -tAc "SELECT 1 FROM pg_database WHERE datname='smartcard_rebuild_test'"
 if($exists -ne '1'){& (Join-Path $PgBin 'createdb.exe') -h 127.0.0.1 -p 54329 -U week1 smartcard_rebuild_test;if($LASTEXITCODE -ne 0){throw 'createdb failed'}}
 $env:TEST_DATABASE_URL='postgresql://week1@127.0.0.1:54329/smartcard_rebuild_test'
 Push-Location (Join-Path $root 'backend')
 try{
  & $Node node_modules/typescript/bin/tsc --noEmit
  if($LASTEXITCODE -ne 0){throw 'TypeScript check failed'}
  & $Node --test --test-reporter=tap --test-concurrency=1 test/integration.test.ts 2>&1 | Tee-Object -FilePath (Join-Path $evidence 'postgres-integration.tap')
  if($LASTEXITCODE -ne 0){throw 'Integration tests failed'}
 }finally{Pop-Location}
}finally{
 $env:TEST_DATABASE_URL=$prior
 if($started){& (Join-Path $PgBin 'pg_ctl.exe') -D $data -w stop}
}
