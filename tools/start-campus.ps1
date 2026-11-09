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
$data=Join-Path $root '.work\campus-local'
$ownerPasswordFile=Join-Path $root '.work\campus-owner.pass'
if(!(Test-Path -LiteralPath (Join-Path $data 'PG_VERSION'))){
 $randomBytes=New-Object byte[] 32
 $randomGenerator=[System.Security.Cryptography.RandomNumberGenerator]::Create()
 try{$randomGenerator.GetBytes($randomBytes)}finally{$randomGenerator.Dispose()}
 [Convert]::ToBase64String($randomBytes).Replace('+','-').Replace('/','_').TrimEnd('=') | Set-Content -LiteralPath $ownerPasswordFile -NoNewline
 & (Join-Path $PgBin 'initdb.exe') -D $data -U campus_local_owner --auth=scram-sha-256 ('--pwfile='+$ownerPasswordFile) --encoding=UTF8 --locale=C
 if($LASTEXITCODE -ne 0){throw 'Cannot initialize local cluster'}
}
$started=$false
$prior=$env:CAMPUS_LOCAL_DATABASE_URL
$priorPgPassword=$env:PGPASSWORD
try{
 $env:PGPASSWORD=(Get-Content -LiteralPath $ownerPasswordFile -Raw).Trim()
 & (Join-Path $PgBin 'pg_ctl.exe') -D $data -l (Join-Path $root '.work\campus-local.log') -o '-h 127.0.0.1 -p 54332' -w start
 if($LASTEXITCODE -ne 0){throw 'Cannot start local cluster; inspect port 54332 before continuing'}
 $started=$true
 $exists=& (Join-Path $PgBin 'psql.exe') -h 127.0.0.1 -p 54332 -U campus_local_owner -d postgres -tAc "SELECT 1 FROM pg_database WHERE datname='smartcampus_local'"
 if($LASTEXITCODE -ne 0){throw 'Cannot query local cluster'}
 if($exists -ne '1'){& (Join-Path $PgBin 'createdb.exe') -h 127.0.0.1 -p 54332 -U campus_local_owner smartcampus_local;if($LASTEXITCODE -ne 0){throw 'Cannot create local database'}}
 $env:CAMPUS_LOCAL_DATABASE_URL='postgresql://campus_local_owner:'+ [uri]::EscapeDataString($env:PGPASSWORD)+'@127.0.0.1:54332/smartcampus_local'
 & $Node (Join-Path $root 'backend\local.ts')
 if($LASTEXITCODE -ne 0){throw 'Local migration/seed failed'}
 Write-Host 'Smart Campus local: http://localhost:8081 . Tài khoản: source/.work/campus-access.txt . Ctrl+C để dừng.'
 & $Node ('--env-file='+ (Join-Path $root '.work\campus.env')) (Join-Path $root 'backend\server.ts')
 if($LASTEXITCODE -ne 0){throw 'Backend stopped with an error'}
}finally{
 $env:CAMPUS_LOCAL_DATABASE_URL=$prior
 $env:PGPASSWORD=$priorPgPassword
 if($started){& (Join-Path $PgBin 'pg_ctl.exe') -D $data -w stop}
}
