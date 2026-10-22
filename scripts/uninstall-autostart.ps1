# Remove the autostart entry and stop the stack.
$ErrorActionPreference = "SilentlyContinue"
. "$PSScriptRoot\_config.ps1"

$StartupDir = [Environment]::GetFolderPath("Startup")
$LnkPath = Join-Path $StartupDir "DSH Mobile Stack.lnk"
$ChildPattern = 'pwa-proxy\.js|dsh-desktop-host\\lib\\cli\.js'

Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" |
    Where-Object { $_.CommandLine -and $_.CommandLine -match 'start\-stack\.ps1' -and $_.ProcessId -ne $PID } |
    ForEach-Object {
        Write-Host "stopping supervisor pid=$($_.ProcessId)"
        Stop-Process -Id $_.ProcessId -Force
    }

foreach ($port in @($Cfg.WebPort, $Cfg.PwaPort)) {
    Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue | ForEach-Object {
        $proc = Get-CimInstance Win32_Process -Filter "ProcessId=$($_.OwningProcess)"
        if ($proc -and $proc.CommandLine -and ($proc.CommandLine -match $ChildPattern)) {
            Write-Host "stopping pid=$($proc.ProcessId) on port $port"
            Stop-Process -Id $proc.ProcessId -Force
        }
    }
}

if (Test-Path $LnkPath) {
    Remove-Item $LnkPath -Force
    Write-Host "removed: $LnkPath"
} else {
    Write-Host "no startup shortcut found"
}

Write-Host ""
Write-Host "The Tailscale Serve route is kept. Remove it with:"
Write-Host "  `"$($Cfg.TailscaleExe)`" serve --https=$($Cfg.ServePort) off"
