# LAN mode: serve the web GUI on a concrete local IPv4 address (same Wi-Fi, no Tailscale).
# Foreground process - Ctrl+C to stop.
$ErrorActionPreference = "Stop"
. "$PSScriptRoot\_config.ps1"

$bind = $Cfg.LanBind
if ([string]::IsNullOrEmpty($bind)) {
    $candidate = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Where-Object {
            $_.IPAddress -notlike "127.*" -and
            $_.IPAddress -notlike "169.254.*" -and
            $_.InterfaceAlias -notmatch "Tailscale|Loopback"
        } | Select-Object -First 1
    if ($candidate) { $bind = $candidate.IPAddress }
}
if ([string]::IsNullOrEmpty($bind)) {
    throw "Set 'lanBind' in config/settings.json (a concrete local IPv4 address)."
}

$port = if ($env:DSH_MOBILE_LAN_PORT) { [int]$env:DSH_MOBILE_LAN_PORT } else { 3080 }
Write-Host "LAN mode: http://${bind}:$port/  (phone must be on the same network)"
Write-Host "Open the tokenized URL printed below once, then the cookie keeps you signed in."
& $Cfg.DshCli web --host $bind --port $port --no-open
