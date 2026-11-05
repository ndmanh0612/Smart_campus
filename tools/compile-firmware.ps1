param([switch]$Provisioned,[string]$Fqbn='esp32:esp32:esp32')
$ErrorActionPreference='Stop'
$root=(Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$tool=Join-Path $root '.work\toolchains\arduino'
$cli=Join-Path $tool 'arduino-cli.exe'
if(!(Test-Path -LiteralPath $cli)){throw 'Run python tools/install-arduino.py first'}
$sketch=Join-Path $root '.work\firmware-build\smart_campus'
New-Item -ItemType Directory -Force -Path $sketch | Out-Null
Copy-Item -LiteralPath (Join-Path $root 'firmware\smart_campus\smart_campus.ino') -Destination (Join-Path $sketch 'smart_campus.ino')
$secretFile=if($Provisioned){Join-Path $root 'firmware\smart_campus\secrets.h'}else{Join-Path $root 'firmware\smart_campus\secrets.example.h'}
if(!(Test-Path -LiteralPath $secretFile)){throw 'Provision secrets.h locally first; never commit it'}
Copy-Item -LiteralPath $secretFile -Destination (Join-Path $sketch 'secrets.h')
$log=Join-Path $root '.work\firmware-compile.log'
& $cli --config-file (Join-Path $tool 'arduino-cli.yaml') compile --jobs 1 --fqbn $Fqbn --build-path (Join-Path $sketch 'build') $sketch *> $log
$exitCode=$LASTEXITCODE
# Provisioned logs stay private in .work; evidence never contains source secrets.
$record=@{status=if($exitCode -eq 0){'PASS'}else{'FAIL'};fqbn=$Fqbn;provisioned=[bool]$Provisioned;hardware_test='NOT_RUN';source_sha256=(Get-FileHash -LiteralPath (Join-Path $sketch 'smart_campus.ino') -Algorithm SHA256).Hash;compiler_log='.work/firmware-compile.log';note='Compile only; no upload/reader/LCD test'}
$record | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $root 'docs\evidence\firmware-compile.json')
if($exitCode -ne 0){if(!$Provisioned){Get-Content -LiteralPath $log -Tail 60};throw 'Firmware compile failed; see private compiler log'}
Write-Output 'Firmware compile PASS. Hardware scan/flash NOT_RUN.'
