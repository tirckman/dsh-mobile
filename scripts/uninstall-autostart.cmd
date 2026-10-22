@echo off
echo Removing dsh-mobile autostart...
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0uninstall-autostart.ps1"
echo.
pause
