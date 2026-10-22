@echo off
setlocal
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Setup.ps1"
if %ERRORLEVEL% neq 0 (
    echo.
    echo Setup encountered an error. Press any key to exit...
    pause >nul
)
