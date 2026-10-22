@echo off
echo Installing dsh-mobile autostart...
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0install-autostart.ps1"
echo.
pause
