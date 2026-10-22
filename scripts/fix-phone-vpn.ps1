# Keep the phone's VPN (Tailscale) alive under aggressive Android/MIUI battery management.
# Requires the phone connected over adb with USB debugging enabled.
$ErrorActionPreference = "Continue"
. "$PSScriptRoot\_config.ps1"

$adb = $Cfg.AdbExe
$vpnPackage = "com.tailscale.ipn"

$serial = (& $adb devices 2>$null | Select-String -Pattern "\sdevice$" |
    ForEach-Object { ($_.Line -split "\s+")[0] } | Select-Object -First 1)
if (-not $serial) {
    Write-Host "No adb device found. Connect the phone with USB debugging enabled."
    exit 1
}
Write-Host "device: $serial"

function Run([string]$cmd) {
    Write-Host "> adb shell $cmd"
    & $adb -s $serial shell $cmd 2>&1 | ForEach-Object { Write-Host "  $_" }
}

Run "settings put secure always_on_vpn_app $vpnPackage"
Run "settings put secure always_on_vpn_lockdown 0"
Run "dumpsys deviceidle whitelist +$vpnPackage"
Run "cmd appops set $vpnPackage RUN_IN_BACKGROUND allow"
Run "cmd appops set $vpnPackage RUN_ANY_IN_BACKGROUND allow"
Run "am start -n $vpnPackage/.MainActivity"

Start-Sleep -Seconds 6
Write-Host ""
Write-Host "=== verify ==="
Run "settings get secure always_on_vpn_app"
Run "settings get secure always_on_vpn_lockdown"
& $adb -s $serial shell "dumpsys deviceidle whitelist" 2>&1 | Select-String $vpnPackage | ForEach-Object { Write-Host "  $_" }

Write-Host ""
Write-Host "Two settings remain manual (Android/MIUI does not expose them to adb):"
Write-Host "  Settings > Apps > Tailscale > Battery > No restrictions"
Write-Host "  Settings > Apps > Tailscale > Autostart > Allow   (MIUI/HyperOS)"
Write-Host "Then unplug USB and check that 'tailscale status' still shows the phone online."
