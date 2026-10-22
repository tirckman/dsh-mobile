@echo off
rem Launch the PWA shell proxy. Called by start-stack.ps1 (env is inherited).
set "NODE=%DSH_MOBILE_NODE%"
if "%NODE%"=="" set "NODE=node"
"%NODE%" "%~dp0..\proxy\pwa-proxy.js"
exit /b %errorlevel%
