@echo off
setlocal
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Uninstall.ps1"
if %ERRORLEVEL% neq 0 (
    echo.
    echo Uninstall encountered an error. See the messages above.
)
echo.
echo Press any key to close this window...
pause >nul
