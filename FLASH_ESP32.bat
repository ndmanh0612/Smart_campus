@echo off
setlocal enabledelayedexpansion
title NAP FIRMWARE ESP32-S3 - SMART CAMPUS

echo ================================================================
echo           NAP FIRMWARE ESP32-S3 TU DONG - SMART CAMPUS
echo ================================================================
echo.

set "SCRIPT_DIR=%~dp0"
if exist "%SCRIPT_DIR%smart_campus\.work\toolchains\arduino\arduino-cli.exe" (
    set "PROJECT_ROOT=%SCRIPT_DIR%smart_campus"
) else if exist "%SCRIPT_DIR%.work\toolchains\arduino\arduino-cli.exe" (
    set "PROJECT_ROOT=%SCRIPT_DIR%"
) else (
    echo [LOI] Khong tim thay thu muc smart_campus!
    goto :FAIL
)

set "CLI=%PROJECT_ROOT%\.work\toolchains\arduino\arduino-cli.exe"
set "CONFIG=%PROJECT_ROOT%\.work\toolchains\arduino\arduino-cli.yaml"
if exist "%PROJECT_ROOT%\firmware\MqttCampusRFID\MqttCampusRFID.ino" (
    set "SKETCH=%PROJECT_ROOT%\firmware\MqttCampusRFID"
) else (
    set "SKETCH=%PROJECT_ROOT%\.work\MqttCampusRFID"
)
set "FQBN=esp32:esp32:esp32s3:FlashSize=16M,PSRAM=opi,PartitionScheme=app3M_fat9M_16MB,CDCOnBoot=cdc,UploadSpeed=512000"

echo [1/3] Kiem tra ket noi ESP32 tren cong COM...
set "TARGET_PORT=COM9"

echo [2/3] Dang bien dich firmware (Compile)...
"%CLI%" compile --config-file "%CONFIG%" --fqbn "%FQBN%" "%SKETCH%"
if %ERRORLEVEL% neq 0 (
    echo [LOI] Bien dich that bai! Vui long kiem tra code trong MqttCampusRFID.ino.
    goto :FAIL
)
echo       Bien dich thanh cong!

echo.
echo [3/3] Dang nap firmware vao ESP32 (%TARGET_PORT%)...
taskkill /f /im serial-monitor.exe > nul 2>&1
"%CLI%" upload -p %TARGET_PORT% --config-file "%CONFIG%" --fqbn "%FQBN%" "%SKETCH%"
if %ERRORLEVEL% neq 0 (
    echo.
    echo [LOI] Nap firmware that bai!
    echo * Nguyen nhan pho bien:
    echo   1. Cong %TARGET_PORT% dang bi chiem boi Arduino IDE Serial Monitor (hay tat no di).
    echo   2. ESP32 chua duoc cam chac hoac khong phai cong %TARGET_PORT%.
    goto :FAIL
)

echo.
echo ================================================================
echo               NAP FIRMWARE THANH CONG!
echo ================================================================
echo ESP32 dang khoi dong lai va se tu dong ket noi WiFi.
echo.
pause
exit /b 0

:FAIL
echo.
echo ================================================================
echo                CO LOI XAY RA!
echo ================================================================
echo.
pause
exit /b 1
