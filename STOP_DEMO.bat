@echo off
chcp 65001 > nul
title Smart Campus - Dung he thong
echo ========================================================
echo             DUNG TOAN BO HE THONG SMART CAMPUS
echo ========================================================
echo.

set "ROOT=%~dp0"
set "SC_DIR="
if exist "%ROOT%smart_campus\.work" set "SC_DIR=%ROOT%smart_campus"
if exist "%ROOT%.work" set "SC_DIR=%ROOT%"
if "%SC_DIR:~-1%"=="\" set "SC_DIR=%SC_DIR:~0,-1%"

echo Dang tat Backend Server...
taskkill /F /FI "WINDOWTITLE eq SmartCampus-Backend*" > nul 2>&1

echo Dang tat Database PostgreSQL...
if exist "%SC_DIR%\.work\pg\package\native\bin\pg_ctl.exe" (
    "%SC_DIR%\.work\pg\package\native\bin\pg_ctl.exe" stop -D "%SC_DIR%\.work\rfid-pg" -m fast > nul 2>&1
)
taskkill /F /IM postgres.exe > nul 2>&1
if exist "%SC_DIR%\.work\rfid-pg\postmaster.pid" del /f /q "%SC_DIR%\.work\rfid-pg\postmaster.pid" > nul 2>&1

echo.
echo Da dung thanh cong toan bo he thong!
ping 127.0.0.1 -n 3 > nul
