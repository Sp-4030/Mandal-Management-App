@echo off
title Hindvi Mandal - Signaling Server & Ngrok
cd /d "%~dp0"

echo ============================================================
echo   HINDVI SWARAJYA MANDAL - SERVER INITIALIZATION
echo ============================================================
echo.

rem 1. Environment check
if exist "C:\flutter\bin" set "PATH=%PATH%;C:\flutter\bin"
if exist "%LOCALAPPDATA%\flutter\bin" set "PATH=%PATH%;%LOCALAPPDATA%\flutter\bin"
if exist "C:\src\flutter\bin" set "PATH=%PATH%;C:\src\flutter\bin"

where dart >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    where python >nul 2>&1
    if %ERRORLEVEL% NEQ 0 (
        echo [ERROR] Neither Dart nor Python found in PATH.
        echo Please ensure Flutter/Dart or Python is installed.
        pause
        exit /b 1
    )
)

set "NGROK_BIN="
if exist "%~dp0ngrok.exe" (
    set "NGROK_BIN=%~dp0ngrok.exe"
) else (
    where ngrok >nul 2>&1
    if %ERRORLEVEL% EQU 0 set "NGROK_BIN=ngrok"
)

if "%NGROK_BIN%"=="" (
    echo [ERROR] ngrok.exe not found in project folder or system PATH.
    pause
    exit /b 1
)

echo [OK] Environment check passed.
echo.

rem 2. Stop any previous instances on port 8080 and ngrok
for /f "tokens=5" %%a in ('netstat -ano -p tcp ^| findstr /C:":8080 " ^| findstr "LISTENING"') do (
    taskkill /f /pid %%a >nul 2>&1
)
taskkill /f /im ngrok.exe >nul 2>&1

rem 3. Start WebSocket server on Port 8080
where dart >nul 2>&1
if %ERRORLEVEL% EQU 0 (
    start /b cmd /c "dart run server/signaling_server.dart 8080"
) else (
    start /b cmd /c "python server/signaling_server.py 8080"
)

rem Wait 2 seconds for server startup
timeout /t 2 /nobreak >nul

rem 4. Start ngrok tunnel
start /b cmd /c ""%NGROK_BIN%" http 8080 --log=stdout > ngrok.log 2>&1"

rem 5. Detect Public URL via ngrok local API (up to 12 attempts)
set "PUBLIC_URL="
for /l %%i in (1,1,12) do (
    if "!PUBLIC_URL!"=="" (
        for /f "usebackq delims=" %%u in (`powershell -NoProfile -Command "try { $res = Invoke-RestMethod -Uri 'http://127.0.0.1:4040/api/tunnels' -TimeoutSec 1; $url = $res.tunnels[0].public_url; if ($url) { $url -replace '^http', 'ws' } } catch {}" 2^>nul`) do (
            set "PUBLIC_URL=%%u"
        )
        if not "!PUBLIC_URL!"=="" goto :url_found
        timeout /t 1 /nobreak >nul
    )
)

:url_found
if "%PUBLIC_URL%"=="" (
    set "PUBLIC_URL=wss://amino-dropkick-resample.ngrok-free.dev"
)

echo.
echo ============================================================
echo Server Started
echo Local Server: 127.0.0.1
echo Port: 8080
echo ngrok Started
echo Public URL: %PUBLIC_URL%
echo Waiting for connections...
echo ============================================================
echo.
echo * Keep this CMD window open while using Hindvi App remote features.
echo * To stop the server cleanly, double-click 'Stop Server.cmd'.
echo.

rem Keep window open and wait
cmd /k
