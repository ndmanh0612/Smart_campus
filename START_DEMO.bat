@echo off
chcp 65001 > nul
title Smart Campus - Khoi dong he thong

set "ROOT=%~dp0"
set "SC_DIR="

if exist "%ROOT%smart_campus\.work" set "SC_DIR=%ROOT%smart_campus"
if exist "%ROOT%.work" set "SC_DIR=%ROOT%"

if "%SC_DIR%"=="" (
    echo Khong tim thay thu muc smart_campus!
    pause
    exit /b 1
)

if "%SC_DIR:~-1%"=="\" set "SC_DIR=%SC_DIR:~0,-1%"

echo ========================================================
echo          KHOI DONG HE THONG SMART CAMPUS DEMO
echo ========================================================
echo Thu muc: %SC_DIR%
echo.

:: 1. Kiem tra xem Postgres da chay chua
netstat -ano | findstr 127.0.0.1:54334 > nul
if errorlevel 1 goto :START_POSTGRES
echo [1/3] Database PostgreSQL da dang chay.
goto :CHECK_BACKEND

:START_POSTGRES
echo [1/3] Dang khoi dong Database PostgreSQL tren cong 54334...
if exist "%SC_DIR%\.work\rfid-pg\postmaster.pid" del /f /q "%SC_DIR%\.work\rfid-pg\postmaster.pid" > nul 2>&1
if exist "%SC_DIR%\.work\pg\package\native\bin\pg_ctl.exe" (
    "%SC_DIR%\.work\pg\package\native\bin\pg_ctl.exe" start -D "%SC_DIR%\.work\rfid-pg" -l "%SC_DIR%\.work\postgres.log" -o "-h 127.0.0.1 -p 54334" > nul 2>&1
) else (
    start "SmartCampus-DB" /min "%SC_DIR%\.work\pg\package\native\bin\postgres.exe" -D "%SC_DIR%\.work\rfid-pg" -h 127.0.0.1 -p 54334
)
ping 127.0.0.1 -n 4 > nul

:CHECK_BACKEND
:: 2. Kiem tra va khoi dong Backend
netstat -ano | findstr 127.0.0.1:8081 > nul
if errorlevel 1 goto :START_BACKEND
echo [2/3] Backend Server da dang chay.
goto :OPEN_WEB

:START_BACKEND
echo [2/3] Dang khoi dong Backend Server tren cong 8081...
start "SmartCampus-Backend" "%SC_DIR%\backend\run_backend.bat"
ping 127.0.0.1 -n 5 > nul

:OPEN_WEB
:: 3. Mo Web App
echo [3/3] Dang mo Web tren trinh duyet...
start http://localhost:8081

echo.
echo ========================================================
echo   HE THONG DA SAN SANG!
echo   * Web App: http://localhost:8081
echo   * ESP32: Hay bat Hotspot "Hello123" [pass 12121212]
echo ========================================================
echo Cua so nay se tu dong dong sau 5 giay...
ping 127.0.0.1 -n 6 > nul
