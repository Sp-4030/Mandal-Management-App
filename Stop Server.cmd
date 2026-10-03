@echo off
chcp 65001 >nul
setlocal enabledelayedexpansion
title Stop Hindvi Signaling Server

echo ============================================================
echo   HINDVI SWARAJYA APP - STOP SIGNALING SERVER
echo ============================================================
echo.

set SERVER_PORT=8080
set NO_PAUSE=0

for %%x in (%*) do (
    if "%%x"=="--no-pause" (
        set NO_PAUSE=1
    ) else (
        set SERVER_PORT=%%x
    )
)

echo Checking for running signaling server on Port %SERVER_PORT%...

set FOUND=0
for /f "tokens=5" %%a in ('netstat -ano -p tcp ^| findstr /C:":%SERVER_PORT% " ^| findstr "LISTENING"') do (
    set PID=%%a
    if not "!PID!"=="0" (
        echo [INFO] Found server running on PID: !PID!
        taskkill /f /pid !PID! >nul 2>&1
        if !ERRORLEVEL! EQU 0 (
            echo [OK] Signaling Server process !PID! stopped successfully.
            set FOUND=1
        ) else (
            echo [WARN] Could not stop PID !PID!. It may have already exited.
        )
    )
)

taskkill /fi "WINDOWTITLE eq Hindvi PC Signaling Server*" /f >nul 2>&1

if "!FOUND!"=="0" (
    echo [INFO] No active signaling server was found running on Port %SERVER_PORT%.
    echo [INFO] Status: Server is OFF 🔴
) else (
    echo.
    echo ============================================================
    echo   [SUCCESS] Server is OFF 🔴
    echo   PC Signaling Server has been safely stopped.
    echo ============================================================
)

echo.
if "!NO_PAUSE!"=="0" (
    pause
)
