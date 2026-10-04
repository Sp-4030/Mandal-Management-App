@echo off
title Hindvi Mandal Server & Ngrok (1 Window)
cd /d "%~dp0"

rem Add Flutter / Dart to PATH
if exist "C:\flutter\bin" set "PATH=%PATH%;C:\flutter\bin"
if exist "%LOCALAPPDATA%\flutter\bin" set "PATH=%PATH%;%LOCALAPPDATA%\flutter\bin"
if exist "C:\src\flutter\bin" set "PATH=%PATH%;C:\src\flutter\bin"

echo ============================================================
echo      HINDVI SWARAJYA MANDAL - SERVER & NGROK
echo ============================================================
echo.
echo [1/2] Starting Signaling Server on Port 8080...

rem Close any old stuck instance on Port 8080
for /f "tokens=5" %%a in ('netstat -ano -p tcp ^| findstr /C:":8080 " ^| findstr "LISTENING"') do (
    taskkill /f /pid %%a >nul 2>&1
)

rem Start server silently in the background of this exact same window
where dart >nul 2>&1
if %ERRORLEVEL% EQU 0 (
    start /b cmd /c "dart run server/signaling_server.dart 8080" >nul 2>&1
) else (
    start /b cmd /c "python server/signaling_server.py 8080" >nul 2>&1
)

rem Wait 2 seconds for port bind
ping 127.0.0.1 -n 3 >nul

echo [2/2] Starting Ngrok Tunnel...
echo.
echo ============================================================
echo   MOBILE APP URL:
echo   wss://amino-dropkick-resample.ngrok-free.dev
echo ============================================================
echo.
echo   * Keep this ONE window open while using the app.
echo   * Closing this window will stop both Server and Ngrok.
echo.

rem Run ngrok in the foreground of this exact same window
if exist "%~dp0ngrok.exe" (
    "%~dp0ngrok.exe" http 8080
) else (
    ngrok http 8080
)

rem On exit, cleanly stop server
for /f "tokens=5" %%a in ('netstat -ano -p tcp ^| findstr /C:":8080 " ^| findstr "LISTENING"') do (
    taskkill /f /pid %%a >nul 2>&1
)
