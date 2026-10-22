# Read-only status report for the dsh-mobile stack.
$ErrorActionPreference = "SilentlyContinue"
. "$PSScriptRoot\_config.ps1"

Write-Host "=== config ==="
Write-Host "  repo : $($Cfg.RepoRoot)"
Write-Host "  host : $($Cfg.Host)"
Write-Host "  ports: web=$($Cfg.WebPort) pwa=$($Cfg.PwaPort) serve=$($Cfg.ServePort)"

Write-Host "=== supervisor ==="
$sup = Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" |
    Where-Object { $_.CommandLine -and $_.CommandLine -match 'start\-stack\.ps1' }
if ($sup) { $sup | ForEach-Object { Write-Host ("  running pid=" + $_.ProcessId) } }
else { Write-Host "  NOT running (run install-autostart.cmd)" }

Write-Host "=== ports ==="
foreach ($p in @($Cfg.WebPort, $Cfg.PwaPort)) {
    $c = Get-NetTCPConnection -LocalPort $p -State Listen -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($c) { Write-Host ("  {0}: listening (pid={1})" -f $p, $c.OwningProcess) }
    else { Write-Host ("  {0}: DOWN" -f $p) }
}

Write-Host "=== tailscale serve ==="
if (Test-Path $Cfg.TailscaleExe) {
    (& $Cfg.TailscaleExe serve status 2>&1 | Select-Object -First 4) | ForEach-Object { Write-Host "  $_" }
} else {
    Write-Host "  tailscale not found at $($Cfg.TailscaleExe)"
}

Write-Host "=== peers on tailnet ==="
if (Test-Path $Cfg.TailscaleExe) {
    (& $Cfg.TailscaleExe status 2>&1 | Select-Object -Skip 1) | ForEach-Object { Write-Host ("  " + $_.Trim()) }
}

Write-Host "=== https endpoint ==="
$code = (& curl.exe -s -o NUL -w "%{http_code}" --max-time 10 $Cfg.PublicUrl 2>$null)
Write-Host ("  GET {0} -> {1}   (401 = up and authenticated, as expected)" -f $Cfg.PublicUrl, $code)
$apk = (& curl.exe -s -o NUL -w "%{http_code}" --max-time 10 ($Cfg.PublicUrl + "dsh-mobile.apk") 2>$null)
Write-Host ("  GET {0}dsh-mobile.apk -> {1}" -f $Cfg.PublicUrl, $apk)

Write-Host "=== last launch link ==="
if (Test-Path $Cfg.TokenFile) {
    Write-Host ("  " + (Get-Content $Cfg.TokenFile -First 1))
    Write-Host "  (paste into the app's sign-in dialog only if it asks again)"
} else {
    Write-Host "  (none yet)"
}
Write-Host ""
Write-Host "logs: $($Cfg.LogDir)"
