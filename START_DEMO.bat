@echo off
chcp 65001 > nul
title Smart Campus - Khoi dong he thong
setlocal enabledelayedexpansion

set "ROOT=%~dp0"
if exist "%ROOT%smart_campus\.work" (
    set "SC_DIR=%ROOT%smart_campus"
) else if exist "%ROOT%.work" (
    set "SC_DIR=%ROOT%"
) else (
    echo Khong tim thay thu muc smart_campus!
    pause
    exit /b 1
)

echo ========================================================
echo          KHOI DONG HE THONG SMART CAMPUS DEMO
echo ========================================================
echo.

:: 1. Kiem tra xem Postgres da chay chua
netstat -ano | findstr 127.0.0.1:54334 > nul
if %ERRORLEVEL% EQU 0 (
    echo [1/3] Database PostgreSQL da dang chay (Port 54334).
) else (
    echo [1/3] Dang khoi dong Database PostgreSQL (Port 54334)...
    if exist "%SC_DIR%\.work\rfid-pg\postmaster.pid" del /f /q "%SC_DIR%\.work\rfid-pg\postmaster.pid" > nul 2>&1
    start "SmartCampus-DB" /min "%SC_DIR%\.work\pg\package\native\bin\postgres.exe" -D "%SC_DIR%\.work\rfid-pg" -h 127.0.0.1 -p 54334
    timeout /t 3 /nobreak > nul
)

:: 2. Kiem tra va khoi dong Backend
netstat -ano | findstr 127.0.0.1:8081 > nul
if %ERRORLEVEL% EQU 0 (
    echo [2/3] Backend Server da dang chay (Port 8081).
) else (
    echo [2/3] Dang khoi dong Backend Server (Port 8081)...
    cd /d "%SC_DIR%\backend"
    start "SmartCampus-Backend" cmd /k "node --env-file=..\.work\campus.env server.ts"
    timeout /t 3 /nobreak > nul
)

:: 3. Mo Web App
echo [3/3] Dang mo Web tren trinh duyet...
start http://localhost:8081

echo.
echo ========================================================
echo   HE THONG DA SAN SANG!
echo   * Web App: http://localhost:8081
echo   * ESP32: Hay bat Hotspot "Hello123" (pass 12121212)
echo ========================================================
timeout /t 4 > nul
