$ErrorActionPreference='Stop'
$root=(Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$compose=@('compose','--env-file',(Join-Path $root 'deploy\.env'),'-f',(Join-Path $root 'deploy\compose.yaml'))
$restoreDb='smartcampus_restorecheck_'+[guid]::NewGuid().ToString('N')
$containerDump='/tmp/'+$restoreDb+'.dump'
$dump=Join-Path $root ('.work\'+$restoreDb+'.dump')
$created=$false
try{
 $query="SELECT json_build_object('transactions',(SELECT count(*) FROM campus.wallet_transactions),'ledgerEntries',(SELECT count(*) FROM campus.wallet_ledger_entries),'unbalancedTransactions',(SELECT count(*) FROM (SELECT transaction_id FROM campus.wallet_ledger_entries GROUP BY transaction_id HAVING sum(delta_points)<>0) bad),'studentPoints',(SELECT coalesce(sum(a.balance_points),0)::text FROM campus.wallets w JOIN campus.ledger_accounts a ON a.id=w.account_id),'completedOrders',(SELECT count(*) FROM campus.orders WHERE status='COMPLETED'),'completedParking',(SELECT count(*) FROM campus.parking_sessions WHERE status='COMPLETED'))::text"
 $before=& docker @compose exec -T db psql -U schema_owner -d smartcampus -tAc $query
 if($LASTEXITCODE -ne 0){throw 'Cannot read Compose source DB'}
 & docker @compose exec -T db pg_dump -U schema_owner -d smartcampus -Fc --no-owner --no-acl -f $containerDump
 if($LASTEXITCODE -ne 0){throw 'Compose backup failed'}
 & docker @compose exec -T db createdb -U schema_owner $restoreDb
 if($LASTEXITCODE -ne 0){throw 'Cannot create fresh restore DB'}
 $created=$true
 & docker @compose exec -T db pg_restore -U schema_owner --exit-on-error --no-owner --no-acl -d $restoreDb $containerDump
 if($LASTEXITCODE -ne 0){throw 'Compose restore failed'}
 $after=& docker @compose exec -T db psql -U schema_owner -d $restoreDb -tAc $query
 if($LASTEXITCODE -ne 0 -or $before -ne $after){throw 'Restore data mismatch'}
 $snapshot=$before|ConvertFrom-Json
 if($snapshot.unbalancedTransactions -ne 0){throw 'Unbalanced restored ledger'}
 & docker @compose cp ('db:'+$containerDump) $dump
 if($LASTEXITCODE -ne 0){throw 'Cannot retain private backup'}
 @{status='PASS';checkedAt=[DateTime]::UtcNow.ToString('o');schema=$snapshot;backupSha256=(Get-FileHash -LiteralPath $dump -Algorithm SHA256).Hash;scope='Synthetic Compose data; isolated restore and aggregate ledger/domain comparison';backupFile=('.work/'+[IO.Path]::GetFileName($dump))}|ConvertTo-Json -Depth 5|Set-Content -LiteralPath (Join-Path $root 'docs\evidence\compose-backup-restore.json')
 Write-Output 'Compose backup/isolated restore/ledger comparison PASS.'
}finally{
 if($created -and $restoreDb -match '^smartcampus_restorecheck_[0-9a-f]{32}$'){
  & docker @compose exec -T db dropdb -U schema_owner $restoreDb
 }
}
