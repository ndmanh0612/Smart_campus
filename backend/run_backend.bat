@echo off
chcp 65001 > nul
title SmartCampus-Backend
cd /d "%~dp0"
echo [Backend] Dang khoi dong Node.js Server...
node --env-file=..\.work\campus.env server.ts
echo.
echo [Backend] Tien trinh da dung lai!
pause
