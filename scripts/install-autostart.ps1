# Install the dsh-mobile autostart (user level, no admin required).
# Creates a Startup shortcut that starts scripts\start-stack.ps1 hidden at logon,
# stops any running stack instance, then starts it immediately.
$ErrorActionPreference = "Stop"
. "$PSScriptRoot\_config.ps1"

$StartupDir = [Environment]::GetFolderPath("Startup")
$LnkPath = Join-Path $StartupDir "DSH Mobile Stack.lnk"
$Powershell = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
$ChildPattern = 'pwa-proxy\.js|dsh-desktop-host\\lib\\cli\.js'

Write-Host "repository : $($Cfg.RepoRoot)"
Write-Host "host       : $($Cfg.Host)"
Write-Host "ports      : web=$($Cfg.WebPort) pwa=$($Cfg.PwaPort)"
Write-Host "startup    : $StartupDir"

# 1) stop a running stack (only our processes)
foreach ($port in @($Cfg.WebPort, $Cfg.PwaPort)) {
    Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue | ForEach-Object {
        $proc = Get-CimInstance Win32_Process -Filter "ProcessId=$($_.OwningProcess)"
        if ($proc -and $proc.CommandLine -and ($proc.CommandLine -match $ChildPattern)) {
            Write-Host "stopping pid=$($proc.ProcessId) on port $port"
            Stop-Process -Id $proc.ProcessId -Force -ErrorAction SilentlyContinue
        }
    }
}
Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" |
    Where-Object { $_.CommandLine -and $_.CommandLine -match 'start\-stack\.ps1' -and $_.ProcessId -ne $PID } |
    ForEach-Object {
        Write-Host "stopping supervisor pid=$($_.ProcessId)"
        Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
    }
Start-Sleep -Seconds 2

# 2) create the Startup shortcut
$ws = New-Object -ComObject WScript.Shell
$lnk = $ws.CreateShortcut($LnkPath)
$lnk.TargetPath = $Powershell
$lnk.Arguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$($Cfg.StartStack)`""
$lnk.WorkingDirectory = $PSScriptRoot
$lnk.WindowStyle = 7
$lnk.Description = "dsh-mobile stack (dsh web + pwa proxy)"
$lnk.Save()
Write-Host "shortcut created: $LnkPath"

# 3) start it now
Ensure-LogDir
Start-Process -FilePath $Powershell `
    -ArgumentList "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$($Cfg.StartStack)`"" `
    -WindowStyle Hidden
Write-Host "supervisor started, waiting for ports..."

$deadline = (Get-Date).AddSeconds(90)
while ((Get-Date) -lt $deadline) {
    $up1 = [bool](Get-NetTCPConnection -LocalPort $Cfg.WebPort -State Listen -ErrorAction SilentlyContinue)
    $up2 = [bool](Get-NetTCPConnection -LocalPort $Cfg.PwaPort -State Listen -ErrorAction SilentlyContinue)
    if ($up1 -and $up2) { break }
    Start-Sleep -Seconds 2
}

Write-Host ""
& $Powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "status.ps1")
