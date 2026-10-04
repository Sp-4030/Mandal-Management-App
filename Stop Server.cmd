@echo off
title Hindvi Mandal - Stop Server
cd /d "%~dp0"

echo ============================================================
echo   HINDVI SWARAJYA MANDAL - STOPPING SERVER & NGROK
echo ============================================================
echo.

rem 1. Kill any process listening on port 8080
echo [1/3] Stopping Signaling Server on port 8080...
for /f "tokens=5" %%a in ('netstat -ano -p tcp ^| findstr /C:":8080 " ^| findstr "LISTENING"') do (
    taskkill /f /pid %%a >nul 2>&1
)

rem 2. Kill ngrok.exe
echo [2/3] Stopping ngrok tunnel...
taskkill /f /im ngrok.exe >nul 2>&1

rem 3. Clean temporary ngrok log
echo [3/3] Cleaning resources...
if exist ngrok.log del /f /q ngrok.log >nul 2>&1

echo.
echo ============================================================
echo Signaling server stopped.
echo ngrok stopped.
echo All resources cleaned successfully.
echo ============================================================
echo.
timeout /t 3 >nul
