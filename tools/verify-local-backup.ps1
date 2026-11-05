param([string]$PgBin='C:\Program Files\PostgreSQL\17\bin')
$ErrorActionPreference='Stop'
$root=(Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$prior=$env:PGPASSWORD
$restoreDb='smartcampus_restorecheck_'+[guid]::NewGuid().ToString('N')
$dump=Join-Path $root ('.work\'+$restoreDb+'.dump')
$created=$false
try{
 $env:PGPASSWORD=(Get-Content -LiteralPath (Join-Path $root '.work\campus-owner.pass') -Raw).Trim()
 $connection=@('-h','127.0.0.1','-p','54332','-U','campus_local_owner')
 $query="SELECT json_build_object('students',(SELECT count(*) FROM campus.students),'transactions',(SELECT count(*) FROM campus.wallet_transactions),'balancePoints',(SELECT coalesce(sum(balance_points),0)::text FROM campus.ledger_accounts),'migrations',(SELECT string_agg(version,',' ORDER BY version) FROM campus.schema_migrations))::text"
 $before=& (Join-Path $PgBin 'psql.exe') @connection -d smartcampus_local -tAc $query
 if($LASTEXITCODE -ne 0){throw 'Cannot read native local database'}
 & (Join-Path $PgBin 'pg_dump.exe') @connection -d smartcampus_local -Fc --no-owner --no-acl -f $dump
 if($LASTEXITCODE -ne 0){throw 'Backup failed'}
 & (Join-Path $PgBin 'createdb.exe') @connection $restoreDb
 if($LASTEXITCODE -ne 0){throw 'Cannot create unique restore-check database'}
 $created=$true
 & (Join-Path $PgBin 'pg_restore.exe') @connection --exit-on-error --no-owner --no-acl -d $restoreDb $dump
 if($LASTEXITCODE -ne 0){throw 'Restore failed'}
 $after=& (Join-Path $PgBin 'psql.exe') @connection -d $restoreDb -tAc $query
 if($LASTEXITCODE -ne 0 -or $before -ne $after){throw 'Restore verification mismatch'}
 $ready=Invoke-RestMethod -Uri 'http://localhost:8081/readyz' -TimeoutSec 30
 $record=@{status='PASS';checkedAt=[DateTime]::UtcNow.ToString('o');sourceDatabase='smartcampus_local';schema=$before|ConvertFrom-Json;backupSha256=(Get-FileHash -LiteralPath $dump -Algorithm SHA256).Hash;backupFile=('.work/'+[IO.Path]::GetFileName($dump));readiness=$ready;scope='Native local synthetic data; counts/balance/migration comparison, not production recovery SLA'}
 $record | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $root 'docs\evidence\native-upgrade-restore.json')
 Write-Output 'Native readiness/backup/isolated restore PASS. Private backup retained in .work.'
}finally{
 # Only the fresh database created by this invocation may be removed; never the source DB.
 if($created -and $restoreDb -match '^smartcampus_restorecheck_[0-9a-f]{32}$'){
  & (Join-Path $PgBin 'dropdb.exe') -h 127.0.0.1 -p 54332 -U campus_local_owner $restoreDb
 }
 $env:PGPASSWORD=$prior
}
