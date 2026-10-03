@echo off
chcp 65001 >nul
setlocal enabledelayedexpansion
title Hindvi App - PC Signaling Server Manager

cd /d "%~dp0"
set SERVER_PORT=8080

rem If direct command-line arguments are passed
if "%~1"=="--direct" (
    goto DIRECT_START
)
if "%~2"=="--direct" (
    set SERVER_PORT=%~1
    goto DIRECT_START
)

:MENU
cls
echo ============================================================
echo      HINDVI SWARAJYA APP - PC SIGNALING SERVER CONTROL
echo ============================================================
echo.

rem Check live status of Port 8080
set CURRENT_PID=
for /f "tokens=5" %%a in ('netstat -ano -p tcp ^| findstr /C:":%SERVER_PORT% " ^| findstr "LISTENING"') do (
    set CURRENT_PID=%%a
)

if not "!CURRENT_PID!"=="" (
    echo   CURRENT STATUS: [ Server is ON  🟢 ] (Port: %SERVER_PORT%, PID: !CURRENT_PID!)
) else (
    echo   CURRENT STATUS: [ Server is OFF 🔴 ] (Port: %SERVER_PORT%)
)

echo.
echo ============================================================
echo   MENU OPTIONS:
echo ============================================================
echo   [1] Press 1 to Start Server
echo   [2] Press 2 to Stop Server
echo   [3] Press 3 to Check Server Status
echo   [4] Press 4 to Exit
echo ============================================================
echo.

set CHOICE=
set /p CHOICE="Enter your choice (1, 2, 3, or 4): "

if "%CHOICE%"=="1" goto START_SERVER
if "%CHOICE%"=="2" goto STOP_SERVER
if "%CHOICE%"=="3" goto CHECK_STATUS
if "%CHOICE%"=="4" goto EXIT_SCRIPT

echo.
echo [!] Invalid selection "%CHOICE%". Please press 1, 2, 3, or 4.
ping 127.0.0.1 -n 2 >nul
goto MENU

:START_SERVER
echo.
echo ------------------------------------------------------------
echo   STARTING SIGNALING SERVER...
echo ------------------------------------------------------------
echo.

rem Check if already running
set RUNNING_PID=
for /f "tokens=5" %%a in ('netstat -ano -p tcp ^| findstr /C:":%SERVER_PORT% " ^| findstr "LISTENING"') do (
    set RUNNING_PID=%%a
)
if not "!RUNNING_PID!"=="" (
    echo [INFO] Server is ALREADY running on Port %SERVER_PORT%! (PID: !RUNNING_PID!)
    echo [INFO] Status: Server is ON 🟢
    echo.
    pause
    goto MENU
)

rem Detect Dart or Python runtime
set RUNTIME=
where dart >nul 2>nul
if %ERRORLEVEL% EQU 0 (
    set RUNTIME=dart
) else (
    where python >nul 2>nul
    if %ERRORLEVEL% EQU 0 (
        set RUNTIME=python
    ) else (
        if exist "%LOCALAPPDATA%\flutter\bin\dart.bat" (
            set PATH=%PATH%;%LOCALAPPDATA%\flutter\bin
            set RUNTIME=dart
        ) else (
            if exist "C:\src\flutter\bin\dart.bat" (
                set PATH=%PATH%;C:\src\flutter\bin
                set RUNTIME=dart
            )
        )
    )
)

if "!RUNTIME!"=="" (
    echo [ERROR] Neither Dart nor Python was found on this system!
    echo Please ensure Flutter/Dart SDK or Python 3 is installed.
    echo.
    pause
    goto MENU
)

echo [OK] Runtime detected: !RUNTIME!
echo [INFO] Launching server in a dedicated window on Port %SERVER_PORT%...

if "!RUNTIME!"=="dart" (
    if not exist "server\signaling_server.dart" (
        echo [ERROR] Server file server\signaling_server.dart not found!
        echo.
        pause
        goto MENU
    )
    start "Hindvi PC Signaling Server (Port %SERVER_PORT%)" cmd /k "title Hindvi PC Signaling Server (Port %SERVER_PORT%) && cd /d "%~dp0" && dart run server/signaling_server.dart %SERVER_PORT%"
) else (
    if not exist "server\signaling_server.py" (
        echo [ERROR] Server file server\signaling_server.py not found!
        echo.
        pause
        goto MENU
    )
    start "Hindvi PC Signaling Server (Port %SERVER_PORT%)" cmd /k "title Hindvi PC Signaling Server (Port %SERVER_PORT%) && cd /d "%~dp0" && python server/signaling_server.py %SERVER_PORT%"
)

rem Wait 2 seconds for socket bind
ping 127.0.0.1 -n 3 >nul

set VERIFY_PID=
for /f "tokens=5" %%a in ('netstat -ano -p tcp ^| findstr /C:":%SERVER_PORT% " ^| findstr "LISTENING"') do (
    set VERIFY_PID=%%a
)

if not "!VERIFY_PID!"=="" (
    echo.
    echo ============================================================
    echo   [SUCCESS] Server is ON 🟢
    echo   Port: %SERVER_PORT% (PID: !VERIFY_PID!)
    echo ============================================================
    echo.
    echo   Local Connection URLs for Hindvi Mobile App:
    for /f "tokens=2 delims=:" %%i in ('ipconfig ^| findstr /C:"IPv4 Address" /C:"IPv4 पत्ता"') do (
        echo     - ws:%%i:%SERVER_PORT%
    )
    echo.
    echo   * Dedicated server console window has been opened.
    echo   * You can press 2 anytime in this menu to Stop the server.
) else (
    echo.
    echo [!] Server process was started. If it didn't stay open, check the server window for any error.
)

echo.
pause
goto MENU

:STOP_SERVER
echo.
echo ------------------------------------------------------------
echo   STOPPING SIGNALING SERVER...
echo ------------------------------------------------------------
echo.

set KILLED=0
for /f "tokens=5" %%a in ('netstat -ano -p tcp ^| findstr /C:":%SERVER_PORT% " ^| findstr "LISTENING"') do (
    set TARGET_PID=%%a
    if not "!TARGET_PID!"=="0" (
        echo [INFO] Found server running on PID: !TARGET_PID!
        taskkill /f /pid !TARGET_PID! >nul 2>&1
        if !ERRORLEVEL! EQU 0 (
            echo [OK] Stopped server process PID !TARGET_PID!.
            set KILLED=1
        )
    )
)

taskkill /fi "WINDOWTITLE eq Hindvi PC Signaling Server*" /f >nul 2>&1

if "!KILLED!"=="1" (
    echo.
    echo ============================================================
    echo   [SUCCESS] Server is OFF 🔴
    echo   Signaling server safely stopped.
    echo ============================================================
) else (
    echo [INFO] Server was not running on Port %SERVER_PORT%.
    echo [INFO] Status: Server is OFF 🔴
)

echo.
pause
goto MENU

:CHECK_STATUS
echo.
echo ------------------------------------------------------------
echo   SERVER STATUS CHECK
echo ------------------------------------------------------------
echo.

set CHK_PID=
for /f "tokens=5" %%a in ('netstat -ano -p tcp ^| findstr /C:":%SERVER_PORT% " ^| findstr "LISTENING"') do (
    set CHK_PID=%%a
)

if not "!CHK_PID!"=="" (
    echo ============================================================
    echo   STATUS: Server is ON 🟢
    echo   PORT:   %SERVER_PORT%
    echo   PID:    !CHK_PID!
    echo ============================================================
    echo.
    echo   Local Connection URLs for Hindvi Mobile App:
    for /f "tokens=2 delims=:" %%i in ('ipconfig ^| findstr /C:"IPv4 Address" /C:"IPv4 पत्ता"') do (
        echo     - ws:%%i:%SERVER_PORT%
    )
) else (
    echo ============================================================
    echo   STATUS: Server is OFF 🔴
    echo   PORT:   %SERVER_PORT% (Not active)
    echo ============================================================
    echo.
    echo   Press 1 to start the server.
)

echo.
pause
goto MENU

:DIRECT_START
echo Starting server directly on port %SERVER_PORT%...
where dart >nul 2>nul
if %ERRORLEVEL% EQU 0 (
    dart run server/signaling_server.dart %SERVER_PORT%
) else (
    python server/signaling_server.py %SERVER_PORT%
)
exit /b %ERRORLEVEL%

:EXIT_SCRIPT
echo.
echo Exiting Hindvi Server Manager.
exit /b 0
