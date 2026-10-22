# USB mode: phone reaches the desktop through the cable (adb reverse), no Wi-Fi required.
# Foreground process - Ctrl+C to stop.
$ErrorActionPreference = "Stop"
. "$PSScriptRoot\_config.ps1"

$adb = $Cfg.AdbExe
$port = $Cfg.UsbWebPort

$serial = (& $adb devices 2>$null | Select-String -Pattern "\sdevice$" |
    ForEach-Object { ($_.Line -split "\s+")[0] } | Select-Object -First 1)
if (-not $serial) {
    throw "No adb device. Plug the phone in with USB debugging enabled."
}

Write-Host "device: $serial"
& $adb -s $serial reverse "tcp:$port" "tcp:$port"
Write-Host "adb reverse tcp:$port established"
Write-Host "On the phone open: http://127.0.0.1:$port/"
Write-Host "First load shows 'authentication required' - retype the address or tap reload once."
Write-Host ""
& $Cfg.DshCli web --host 127.0.0.1 --port $port --no-open
