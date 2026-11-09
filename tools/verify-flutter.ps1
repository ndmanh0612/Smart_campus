param([ValidateSet('all','web','apk')][string]$Stage='all')
$ErrorActionPreference='Stop'
$root=(Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
try {
    $fso = New-Object -ComObject Scripting.FileSystemObject
    $short = $fso.GetFolder($root).ShortPath
    if ($short) { $root = $short }
} catch {}
$flutter=Join-Path $root '.work\toolchains\flutter\bin\flutter.bat'
$app=Join-Path $root 'flutter\app'
if(!(Test-Path -LiteralPath $flutter) -or !(Test-Path -LiteralPath (Join-Path $app 'pubspec.yaml'))){throw 'Install the local SDK and scaffold app first; see README'}
$tmp=Join-Path $root '.work\jtmp'
New-Item -ItemType Directory -Force -Path $tmp | Out-Null
$settings=@{
 ANDROID_HOME=(Join-Path $root '.work\toolchains\android-sdk')
 ANDROID_SDK_ROOT=(Join-Path $root '.work\toolchains\android-sdk')
 ANDROID_USER_HOME=(Join-Path $root '.work\android-user')
 GRADLE_USER_HOME=(Join-Path $root '.work\gradle')
 PUB_CACHE=(Join-Path $root '.work\pub-cache')
 JAVA_HOME='C:\Program Files\Microsoft\jdk-21.0.1.12-hotspot'
 CI='true'
 FLUTTER_SUPPRESS_ANALYTICS='true'
 DART_SUPPRESS_ANALYTICS='true'
 APPDATA=(Join-Path $root '.work\flutter-user')
}
$settings['JAVA_TOOL_OPTIONS']=$env:JAVA_TOOL_OPTIONS+' -Djdk.net.unixdomain.tmpdir="'+$tmp+'"'
$settings['PATH']='C:\Users\dellcuatri142\.cache\codex-runtimes\codex-primary-runtime\dependencies\native\git\cmd;'+$env:PATH
$prior=@{}
foreach($name in $settings.Keys){$prior[$name]=[Environment]::GetEnvironmentVariable($name,'Process');[Environment]::SetEnvironmentVariable($name,$settings[$name],'Process')}
$priorErrorAction = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
if (Test-Path variable:PSNativeCommandUseErrorActionPreference) {
    $priorNativeError = $PSNativeCommandUseErrorActionPreference
    $PSNativeCommandUseErrorActionPreference = $false
}
Push-Location $app
try{
 if($Stage -eq 'all'){
  & $flutter analyze 2>&1 | Tee-Object -FilePath (Join-Path $root 'docs\evidence\flutter-analyze.txt');if($LASTEXITCODE -ne 0){throw 'Analyze failed'}
  & $flutter test 2>&1 | Tee-Object -FilePath (Join-Path $root 'docs\evidence\flutter-test.txt');if($LASTEXITCODE -ne 0){throw 'Widget test failed'}
 }
 if($Stage -in @('all','web')){
  & $flutter build web --release --no-web-resources-cdn 2>&1 | Tee-Object -FilePath (Join-Path $root 'docs\evidence\build-web.txt');if($LASTEXITCODE -ne 0){throw 'Web build failed'}
  Copy-Item -LiteralPath 'assets\fonts\LICENSE.txt' -Destination 'build\web\assets\fonts\LICENSE.txt'
 }
 if($Stage -in @('all','apk')){
  & $flutter build apk --debug 2>&1 | Tee-Object -FilePath (Join-Path $root 'docs\evidence\build-apk.txt');if($LASTEXITCODE -ne 0){throw 'APK build failed'}
  Get-FileHash -LiteralPath 'build\app\outputs\flutter-apk\app-debug.apk' -Algorithm SHA256 | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $root 'docs\evidence\apk-sha256.json')
 }
}finally{
 Pop-Location
 foreach($name in $prior.Keys){[Environment]::SetEnvironmentVariable($name,$prior[$name],'Process')}
}
