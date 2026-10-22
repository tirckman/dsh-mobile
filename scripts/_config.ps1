# Shared configuration loader for dsh-mobile scripts.
#   . "$PSScriptRoot\_config.ps1"      (from scripts\)
#   . "$PSScriptRoot\..\scripts\_config.ps1"   (from build\)
# Precedence: environment variable > config/settings.json > built-in default.
$ErrorActionPreference = "Stop"

$RepoRoot = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
$SettingsPath = Join-Path $RepoRoot "config\settings.json"
if (-not (Test-Path $SettingsPath)) {
    throw "config/settings.json not found. Copy config/settings.example.json to config/settings.json and edit it."
}

$settingsJson = [System.IO.File]::ReadAllText($SettingsPath, [System.Text.Encoding]::UTF8) | ConvertFrom-Json

function Get-ConfigValue([string]$envName, $fileValue, $default) {
    $fromEnv = [Environment]::GetEnvironmentVariable($envName)
    if (-not [string]::IsNullOrEmpty($fromEnv)) { return $fromEnv }
    if ($null -ne $fileValue -and "$fileValue" -ne "") { return $fileValue }
    return $default
}

function Expand-ConfigPath($value) {
    if ($null -eq $value) { return $null }
    return [Environment]::ExpandEnvironmentVariables([string]$value)
}

$Cfg = [ordered]@{
    Host        = [string](Get-ConfigValue "DSH_MOBILE_HOST" $settingsJson.host $null)
    WebPort     = [int](Get-ConfigValue "DSH_MOBILE_WEB_PORT" $settingsJson.webPort 3081)
    PwaPort     = [int](Get-ConfigValue "DSH_MOBILE_PWA_PORT" $settingsJson.pwaPort 3082)
    ServePort   = [int](Get-ConfigValue "DSH_MOBILE_SERVE_PORT" $settingsJson.servePort 443)
    AppName     = [string](Get-ConfigValue "DSH_MOBILE_APP_NAME" $settingsJson.appName "DeepSeek Harness")

    DshCli      = Expand-ConfigPath (Get-ConfigValue "DSH_MOBILE_DSH_CLI" $settingsJson.dshCli "$env:LOCALAPPDATA\Programs\DeepSeek Harness\resources\runtime\cli\bin\dsh.cmd")
    NodeExe     = Expand-ConfigPath (Get-ConfigValue "DSH_MOBILE_NODE" $settingsJson.nodeExe "$env:USERPROFILE\.dsh\dsh-runtimes\dsh-primary-runtime\dependencies\node\bin\node.exe")
    TailscaleExe= Expand-ConfigPath (Get-ConfigValue "DSH_MOBILE_TAILSCALE" $settingsJson.tailscaleExe "C:\Program Files\Tailscale\tailscale.exe")
    AdbExe      = Expand-ConfigPath (Get-ConfigValue "DSH_MOBILE_ADB" $settingsJson.adbExe "adb")

    AndroidPackage = [string](Get-ConfigValue "DSH_MOBILE_PACKAGE" $settingsJson.androidPackage "com.deepseek.harness.mobile")
    BuildRoot      = Expand-ConfigPath (Get-ConfigValue "DSH_MOBILE_BUILD_ROOT" $settingsJson.buildRoot "C:\dsh-apk-build")
    KeystorePath   = Expand-ConfigPath (Get-ConfigValue "DSH_MOBILE_KEYSTORE" $settingsJson.keystorePath "C:\dsh-apk-build\dsh-mobile.keystore")
    KeystoreAlias  = [string](Get-ConfigValue "DSH_MOBILE_KEY_ALIAS" $settingsJson.keystoreAlias "dsh")
    KeystorePass   = [string](Get-ConfigValue "DSH_MOBILE_KEY_PASS" $settingsJson.keystorePass "dshmobile")
    AndroidJdk     = Expand-ConfigPath (Get-ConfigValue "DSH_MOBILE_JDK" $settingsJson.androidJdk "")
    AndroidBuildTools = Expand-ConfigPath (Get-ConfigValue "DSH_MOBILE_BUILD_TOOLS" $settingsJson.androidBuildTools "")
    AndroidJar     = Expand-ConfigPath (Get-ConfigValue "DSH_MOBILE_ANDROID_JAR" $settingsJson.androidJar "")

    LanBind     = [string](Get-ConfigValue "DSH_MOBILE_LAN_BIND" $settingsJson.lanBind "")
    UsbWebPort  = [int](Get-ConfigValue "DSH_MOBILE_USB_PORT" $settingsJson.usbWebPort 3081)
    LogDir      = Expand-ConfigPath (Get-ConfigValue "DSH_MOBILE_LOG_DIR" $settingsJson.logDir "$env:LOCALAPPDATA\dsh-mobile\logs")
}

if ([string]::IsNullOrWhiteSpace($Cfg.Host) -or $Cfg.Host -like "your-desktop*") {
    throw "Set 'host' in config/settings.json (your Tailscale MagicDNS name or a LAN address)."
}

$Cfg.RepoRoot = $RepoRoot
$Cfg.SettingsPath = $SettingsPath
$Cfg.TokenFile = Join-Path $Cfg.LogDir "last-token.txt"
$Cfg.RunWebCmd = Join-Path $RepoRoot "scripts\run-web.cmd"
$Cfg.RunProxyCmd = Join-Path $RepoRoot "scripts\run-proxy.cmd"
$Cfg.StartStack = Join-Path $RepoRoot "scripts\start-stack.ps1"
$Cfg.PublicUrl = "https://$($Cfg.Host)/"

function Ensure-LogDir {
    New-Item -ItemType Directory -Force -Path $Cfg.LogDir | Out-Null
}

# Export the settings child processes (run-web.cmd / run-proxy.cmd) rely on.
function Export-ChildEnv {
    $env:DSH_MOBILE_HOST = $Cfg.Host
    $env:DSH_MOBILE_WEB_PORT = [string]$Cfg.WebPort
    $env:DSH_MOBILE_PWA_PORT = [string]$Cfg.PwaPort
    $env:DSH_MOBILE_DSH_CLI = $Cfg.DshCli
    $env:DSH_MOBILE_NODE = $Cfg.NodeExe
    $env:DSH_MOBILE_APP_NAME = $Cfg.AppName
}
