# Download a minimal Android build toolchain (JDK 17 + build-tools + platform android.jar).
#
#   powershell -ExecutionPolicy Bypass -File build\setup-toolchain.ps1
#   powershell -ExecutionPolicy Bypass -File build\setup-toolchain.ps1 -BuildRoot D:\android-build
#
# Mirrors (optional, faster in some regions):
#   -JdkUrl https://mirrors.tuna.tsinghua.edu.cn/Adoptium/17/jdk/x64/windows/OpenJDK17U-jdk_x64_windows_hotspot_17.0.20.1_1.zip
param(
    [string]$BuildRoot = "C:\dsh-apk-build",
    [string]$JdkUrl = "https://api.adoptium.net/v3/binary/latest/17/ga/windows/x64/jdk/hotspot/normal/eclipse",
    [string]$BuildToolsUrl = "https://dl.google.com/android/repository/build-tools_r35_windows.zip",
    [string]$PlatformUrl = "https://dl.google.com/android/repository/platform-35_r02.zip"
)
$ErrorActionPreference = "Stop"

if ($BuildRoot -match '[^\x00-\x7F]') {
    throw "BuildRoot must be an ASCII-only path (aapt2 cannot handle non-ASCII paths): $BuildRoot"
}
New-Item -ItemType Directory -Force -Path $BuildRoot | Out-Null
Write-Host "build root: $BuildRoot"

function Fetch([string]$url, [string]$target) {
    if (Test-Path $target) {
        Write-Host "  exists: $target"
        return
    }
    Write-Host "  downloading $url"
    if (Get-Command curl.exe -ErrorAction SilentlyContinue) {
        & curl.exe -sSL --retry 3 --max-time 900 -o $target $url
        if ($LASTEXITCODE -ne 0) { throw "download failed: $url" }
    } else {
        Invoke-WebRequest -Uri $url -OutFile $target -UseBasicParsing
    }
    Write-Host ("  ok: {0:N1} MB" -f ((Get-Item $target).Length / 1MB))
}

function Extract([string]$zip) {
    Write-Host "  extracting $(Split-Path -Leaf $zip)"
    tar -xf $zip -C $BuildRoot
    if ($LASTEXITCODE -ne 0) { throw "extract failed: $zip" }
}

Write-Host "[1/3] JDK"
$jdkZip = Join-Path $BuildRoot "jdk17.zip"
$haveJdk = Get-ChildItem $BuildRoot -Directory -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -like "jdk-17*" -or $_.Name -like "jdk-21*" } | Select-Object -First 1
if (-not $haveJdk) {
    Fetch $JdkUrl $jdkZip
    Extract $jdkZip
}

Write-Host "[2/3] Android build-tools"
$haveAapt2 = Get-ChildItem $BuildRoot -Filter aapt2.exe -Recurse -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -notmatch '\\lib\\' } | Select-Object -First 1
if (-not $haveAapt2) {
    $btZip = Join-Path $BuildRoot "build-tools.zip"
    Fetch $BuildToolsUrl $btZip
    Extract $btZip
}

Write-Host "[3/3] Android platform (android.jar)"
$haveJar = Get-ChildItem $BuildRoot -Filter android.jar -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $haveJar) {
    $platZip = Join-Path $BuildRoot "platform.zip"
    Fetch $PlatformUrl $platZip
    Extract $platZip
}

# --- report --------------------------------------------------------------
$jdkDir = (Get-ChildItem $BuildRoot -Directory | Where-Object { $_.Name -like "jdk-*" } | Select-Object -First 1).FullName
$aapt2 = (Get-ChildItem $BuildRoot -Filter aapt2.exe -Recurse | Where-Object { $_.FullName -notmatch '\\lib\\' } | Select-Object -First 1).FullName
$buildToolsDir = Split-Path -Parent $aapt2
$androidJar = (Get-ChildItem $BuildRoot -Filter android.jar -Recurse | Select-Object -First 1).FullName

Write-Host ""
Write-Host "toolchain ready:"
Write-Host "  jdk         : $jdkDir"
Write-Host "  build-tools : $buildToolsDir"
Write-Host "  android.jar : $androidJar"
Write-Host ""
Write-Host "Add these to config/settings.json (or keep the auto-detection):"
Write-Host ([ordered]@{
    buildRoot         = $BuildRoot
    androidJdk        = $jdkDir
    androidBuildTools = $buildToolsDir
    androidJar        = $androidJar
} | ConvertTo-Json)
Write-Host ""
Write-Host "Next: powershell -ExecutionPolicy Bypass -File build\build-apk.ps1"
