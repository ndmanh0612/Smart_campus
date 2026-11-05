param([int]$Port=8765)
$ErrorActionPreference='Stop'
if($Port -lt 1024 -or $Port -gt 65535){throw 'Choose a local port from 1024 to 65535'}
$root=(Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$web=Join-Path $root 'flutter\app\build\web'
$python=Join-Path $root '.venv\Scripts\python.exe'
if(!(Test-Path -LiteralPath (Join-Path $web 'index.html'))){throw 'Build Web first or extract the Web artifact; see README'}
Write-Host "Web demo: http://127.0.0.1:$Port . Stop with Ctrl+C. Local static server only, not production hosting."
& $python -m http.server $Port --bind 127.0.0.1 --directory $web
