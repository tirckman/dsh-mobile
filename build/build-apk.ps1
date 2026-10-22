# Build the DSH Android WebView shell into dist/DSH-Mobile.apk.
#
#   powershell -ExecutionPolicy Bypass -File build\build-apk.ps1
#
# Prerequisites: run build\setup-toolchain.ps1 once (or point config/settings.json at an
# existing JDK + Android build-tools + android.jar).
$ErrorActionPreference = "Stop"
. "$PSScriptRoot\..\scripts\_config.ps1"

$AndroidDir = Join-Path $Cfg.RepoRoot "android"
$DistDir = Join-Path $Cfg.RepoRoot "dist"
$BuildRoot = $Cfg.BuildRoot

# aapt2 cannot handle non-ASCII paths on Windows, so build from an ASCII-only copy.
if ($BuildRoot -match '[^\x00-\x7F]') {
    throw "buildRoot must be an ASCII-only path (aapt2 limitation): $BuildRoot"
}
$SrcDir = Join-Path $BuildRoot "src"
$WorkDir = Join-Path $BuildRoot "work"

Write-Host "repo        : $($Cfg.RepoRoot)"
Write-Host "android src : $AndroidDir"
Write-Host "build root  : $BuildRoot"
Write-Host "host        : $($Cfg.Host)  -> $($Cfg.PublicUrl)"

# --- toolchain ---------------------------------------------------------------
function Resolve-Tool([string]$configured, [string]$name) {
    if (-not [string]::IsNullOrEmpty($configured)) {
        if (-not (Test-Path $configured)) { throw "$name configured but missing: $configured" }
        return $configured
    }
    $hit = Get-ChildItem $BuildRoot -Filter $name -Recurse -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -notmatch '\\lib\\' } | Select-Object -First 1
    if (-not $hit) { throw "$name not found under $BuildRoot - run build\setup-toolchain.ps1" }
    return $hit.FullName
}

$jdk = $Cfg.AndroidJdk
if ([string]::IsNullOrEmpty($jdk)) {
    $jdkDir = Get-ChildItem $BuildRoot -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -like "jdk-17*" -or $_.Name -like "jdk-21*" } | Select-Object -First 1
    if (-not $jdkDir) { throw "JDK not found under $BuildRoot - run build\setup-toolchain.ps1" }
    $jdk = $jdkDir.FullName
}
$env:JAVA_HOME = $jdk
$env:PATH = "$jdk\bin;$env:PATH"

$aapt2 = Resolve-Tool $Cfg.AndroidBuildTools "aapt2.exe"
$buildToolsDir = Split-Path -Parent $aapt2
$d8 = Join-Path $buildToolsDir "d8.bat"
$zipalign = Join-Path $buildToolsDir "zipalign.exe"
$apksigner = Join-Path $buildToolsDir "apksigner.bat"
$androidJar = Resolve-Tool $Cfg.AndroidJar "android.jar"
foreach ($t in @($d8, $zipalign, $apksigner)) {
    if (-not (Test-Path $t)) { throw "missing build tool: $t" }
}

Write-Host "jdk         : $jdk"
Write-Host "aapt2       : $aapt2"
Write-Host "android.jar : $androidJar"

# --- stage sources -----------------------------------------------------------
if (Test-Path $SrcDir) { Remove-Item $SrcDir -Recurse -Force }
if (Test-Path $WorkDir) { Remove-Item $WorkDir -Recurse -Force }
New-Item -ItemType Directory -Force -Path $SrcDir, $WorkDir | Out-Null
Copy-Item (Join-Path $AndroidDir "*") $SrcDir -Recurse -Force

# Generate AppConfig.java from the template + configured host.
$template = Get-Content (Join-Path $SrcDir "src\com\deepseek\harness\mobile\AppConfig.java.template") -Raw -Encoding UTF8
$template = $template.Replace("__HOME__", $Cfg.PublicUrl)
# Write without BOM: javac rejects a leading U+FEFF.
$noBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText((Join-Path $SrcDir "src\com\deepseek\harness\mobile\AppConfig.java"), $template, $noBom)

# --- 1. resources ------------------------------------------------------------
$resZip = Join-Path $WorkDir "res.zip"
& $aapt2 compile --dir (Join-Path $SrcDir "res") -o $resZip
if ($LASTEXITCODE -ne 0) { throw "aapt2 compile failed" }

$baseApk = Join-Path $WorkDir "base.apk"
& $aapt2 link -o $baseApk -I $androidJar --manifest (Join-Path $SrcDir "AndroidManifest.xml") -R $resZip --auto-add-overlay
if ($LASTEXITCODE -ne 0) { throw "aapt2 link failed" }

# --- 2. java -> class --------------------------------------------------------
$classesDir = Join-Path $WorkDir "classes"
New-Item -ItemType Directory -Force -Path $classesDir | Out-Null
$sources = @(Get-ChildItem (Join-Path $SrcDir "src") -Filter *.java -Recurse | ForEach-Object { $_.FullName })
& (Join-Path $jdk "bin\javac.exe") -encoding UTF-8 -source 11 -target 11 -nowarn -classpath $androidJar -d $classesDir @sources
if ($LASTEXITCODE -ne 0) { throw "javac failed" }

# --- 3. class -> dex ---------------------------------------------------------
$appJar = Join-Path $WorkDir "app.jar"
& (Join-Path $jdk "bin\jar.exe") cf $appJar -C $classesDir .
$dexDir = Join-Path $WorkDir "dex"
New-Item -ItemType Directory -Force -Path $dexDir | Out-Null
& $d8 --min-api 24 --lib $androidJar --output $dexDir $appJar
if ($LASTEXITCODE -ne 0) { throw "d8 failed" }

# --- 4. insert classes.dex ---------------------------------------------------
$dexPath = Join-Path $dexDir "classes.dex"
$withDex = Join-Path $WorkDir "with-dex.apk"
Copy-Item $baseApk $withDex -Force
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = [System.IO.Compression.ZipFile]::Open($withDex, "Update")
try {
    $entry = $zip.CreateEntry("classes.dex", [System.IO.Compression.CompressionLevel]::Optimal)
    $stream = $entry.Open()
    $bytes = [System.IO.File]::ReadAllBytes($dexPath)
    $stream.Write($bytes, 0, $bytes.Length)
    $stream.Close()
} finally {
    $zip.Dispose()
}

# --- 5. align + sign ---------------------------------------------------------
$aligned = Join-Path $WorkDir "aligned.apk"
& $zipalign -f 4 $withDex $aligned
if ($LASTEXITCODE -ne 0) { throw "zipalign failed" }

$ks = $Cfg.KeystorePath
if (-not (Test-Path $ks)) {
    Write-Host "generating signing key: $ks"
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $ks) | Out-Null
    & (Join-Path $jdk "bin\keytool.exe") -genkeypair -keystore $ks -alias $Cfg.KeystoreAlias -keyalg RSA `
        -keysize 2048 -validity 10000 -storepass $Cfg.KeystorePass -keypass $Cfg.KeystorePass `
        -dname "CN=dsh-mobile, O=dsh-mobile, C=CN"
    if ($LASTEXITCODE -ne 0) { throw "keytool failed" }
}

New-Item -ItemType Directory -Force -Path $DistDir | Out-Null
$finalApk = Join-Path $DistDir "DSH-Mobile.apk"
Remove-Item $finalApk -ErrorAction SilentlyContinue
& $apksigner sign --ks $ks --ks-pass "pass:$($Cfg.KeystorePass)" --key-pass "pass:$($Cfg.KeystorePass)" `
    --out $finalApk $aligned
if ($LASTEXITCODE -ne 0) { throw "apksigner failed" }
& $apksigner verify --print-certs $finalApk | Select-Object -First 3 | ForEach-Object { Write-Host "  $_" }

Write-Host ""
Write-Host "APK: $finalApk"
Write-Host ("SIZE: {0:N1} KB" -f ((Get-Item $finalApk).Length / 1KB))
Write-Host "Install: adb install -r `"$finalApk`""
