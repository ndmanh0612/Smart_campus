@echo off
chcp 65001 > nul
title Smart Campus - Dung he thong
echo ========================================================
echo             DUNG TOAN BO HE THONG SMART CAMPUS
echo ========================================================
echo.

echo Dang tat Backend Server va Database PostgreSQL...
taskkill /F /FI "WINDOWTITLE eq SmartCampus-Backend*" > nul 2>&1
taskkill /F /IM postgres.exe > nul 2>&1

echo Da dung thanh cong!
timeout /t 2 > nul
