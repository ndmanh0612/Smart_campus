param([string]$PgBin='C:\Program Files\PostgreSQL\17\bin',[string]$Node='C:\Users\dellcuatri142\.cache\codex-runtimes\codex-primary-runtime\dependencies\node\bin\node.exe',[string]$TestPattern='')
$ErrorActionPreference='Stop'
$root=(Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$data=Join-Path $root '.work\campus-test'
$evidence=Join-Path $root 'docs\evidence'
New-Item -ItemType Directory -Force -Path $evidence | Out-Null
if(!(Test-Path -LiteralPath (Join-Path $data 'PG_VERSION'))){
 & (Join-Path $PgBin 'initdb.exe') -D $data -U campus_test_owner --auth=trust --encoding=UTF8 --locale=C
 if($LASTEXITCODE -ne 0){throw 'Cannot initialize isolated test cluster'}
}
$started=$false
$prior=$env:CAMPUS_TEST_DATABASE_URL
try{
 & (Join-Path $PgBin 'pg_ctl.exe') -D $data -l (Join-Path $root '.work\campus-test.log') -o '-h 127.0.0.1 -p 54331' -w start
 if($LASTEXITCODE -ne 0){throw 'Cannot start isolated test cluster; inspect ownership of port 54331'}
 $started=$true
 $exists=& (Join-Path $PgBin 'psql.exe') -h 127.0.0.1 -p 54331 -U campus_test_owner -d postgres -tAc "SELECT 1 FROM pg_database WHERE datname='smartcampus_test'"
 if($LASTEXITCODE -ne 0){throw 'Cannot query test cluster'}
 if($exists -ne '1'){
  & (Join-Path $PgBin 'createdb.exe') -h 127.0.0.1 -p 54331 -U campus_test_owner smartcampus_test
  if($LASTEXITCODE -ne 0){throw 'Cannot create dedicated test database'}
 }
 $env:CAMPUS_TEST_DATABASE_URL='postgresql://campus_test_owner@127.0.0.1:54331/smartcampus_test'
 Push-Location (Join-Path $root 'backend')
 try{
  & $Node node_modules/typescript/bin/tsc --noEmit
  if($LASTEXITCODE -ne 0){throw 'TypeScript check failed'}
  $testArgs=@('--test','--test-reporter=tap','--test-concurrency=1')
  if($TestPattern){$testArgs+=('--test-name-pattern='+$TestPattern)}
  $testArgs+='test/campus.test.ts'
  $logName=if($TestPattern){'campus-targeted-tests.tap'}else{'campus-tests.tap'}
  & $Node @testArgs 2>&1 | Tee-Object -FilePath (Join-Path $evidence $logName)
  if($LASTEXITCODE -ne 0){throw 'Smart Campus tests failed'}
 }finally{Pop-Location}
}finally{
 $env:CAMPUS_TEST_DATABASE_URL=$prior
 if($started){& (Join-Path $PgBin 'pg_ctl.exe') -D $data -w stop}
}
