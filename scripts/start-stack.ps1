# dsh-mobile stack supervisor
#
# Keeps two children alive and re-applies the Tailscale Serve route when needed:
#   dsh web      127.0.0.1:<webPort>
#   pwa proxy    127.0.0.1:<pwaPort>   (tailscale serve points here)
#
# Started hidden at logon by the Startup shortcut created by install-autostart.ps1.
$ErrorActionPreference = "SilentlyContinue"
. "$PSScriptRoot\_config.ps1"

Ensure-LogDir
$WebLog = Join-Path $Cfg.LogDir "web.out.log"
$WebErr = Join-Path $Cfg.LogDir "web.err.log"
$ProxyLog = Join-Path $Cfg.LogDir "proxy.out.log"
$ProxyErr = Join-Path $Cfg.LogDir "proxy.err.log"
$SuperLog = Join-Path $Cfg.LogDir "supervisor.log"
$ProxyAppLog = Join-Path $Cfg.LogDir "proxy.app.log"

function Log([string]$msg) {
    $line = "{0} {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $msg
    Add-Content -Path $SuperLog -Value $line -Encoding UTF8
}

# single-instance guard
$myPath = $MyInvocation.MyCommand.Path
$others = Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" |
    Where-Object { $_.CommandLine -and $_.CommandLine.Contains($myPath) -and $_.ProcessId -ne $PID }
if ($others) { exit 0 }

function Test-Port([int]$port) {
    return [bool](Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue)
}

function Ensure-Serve {
    if (-not (Test-Path $Cfg.TailscaleExe)) { return }
    $status = (& $Cfg.TailscaleExe serve status 2>&1 | Out-String)
    if ($status -notmatch "127\.0\.0\.1:$($Cfg.PwaPort)") {
        & $Cfg.TailscaleExe serve --bg "--https=$($Cfg.ServePort)" "http://127.0.0.1:$($Cfg.PwaPort)" *> $null
        Log "serve re-applied -> 127.0.0.1:$($Cfg.PwaPort)"
    }
}

function Update-Token {
    if (-not (Test-Path $WebLog)) { return }
    $lines = Get-Content $WebLog -Tail 40 -ErrorAction SilentlyContinue
    $match = $lines | Select-String -Pattern "dsh web:\s*(https?://\S+)" | Select-Object -Last 1
    if ($match) {
        Set-Content -Path $Cfg.TokenFile -Value $match.Matches[0].Groups[1].Value -Encoding UTF8
    }
}

Export-ChildEnv
$env:DSH_MOBILE_LOG = $ProxyAppLog
Log "supervisor starting (host=$($Cfg.Host) web=$($Cfg.WebPort) pwa=$($Cfg.PwaPort))"

while ($true) {
    Ensure-Serve

    if (-not (Test-Port $Cfg.PwaPort)) {
        Export-ChildEnv
        $env:DSH_MOBILE_LOG = $ProxyAppLog
        Start-Process -FilePath $env:ComSpec -ArgumentList "/c `"$($Cfg.RunProxyCmd)`"" -WindowStyle Hidden `
            -RedirectStandardOutput $ProxyLog -RedirectStandardError $ProxyErr
        Log "proxy start requested"
        Start-Sleep -Seconds 3
    }

    if (-not (Test-Port $Cfg.WebPort)) {
        Export-ChildEnv
        Start-Process -FilePath $env:ComSpec -ArgumentList "/c `"$($Cfg.RunWebCmd)`"" -WindowStyle Hidden `
            -RedirectStandardOutput $WebLog -RedirectStandardError $WebErr
        Log "dsh web start requested"
        Start-Sleep -Seconds 10
        Update-Token
        $token = if (Test-Path $Cfg.TokenFile) { Get-Content $Cfg.TokenFile -First 1 -ErrorAction SilentlyContinue } else { "(pending)" }
        Log "token: $token"
    }

    Start-Sleep -Seconds 10
}
