@echo off
rem Launch dsh web on loopback with the public URL advertised to the browser.
rem Called by start-stack.ps1, which exports DSH_MOBILE_* environment variables.
if "%DSH_MOBILE_DSH_CLI%"=="" (
  echo DSH_MOBILE_DSH_CLI is not set
  exit /b 1
)
if "%DSH_MOBILE_HOST%"=="" (
  echo DSH_MOBILE_HOST is not set
  exit /b 1
)
if "%DSH_MOBILE_WEB_PORT%"=="" set "DSH_MOBILE_WEB_PORT=3081"

"%DSH_MOBILE_DSH_CLI%" web --host 127.0.0.1 --port %DSH_MOBILE_WEB_PORT% --public-url "https://%DSH_MOBILE_HOST%/" --trusted-host "%DSH_MOBILE_HOST%" --no-open
exit /b %errorlevel%
