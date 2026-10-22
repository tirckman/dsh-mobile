# 构建 APK

本项目不用 Gradle / Android Studio，只调用 Android SDK 里的四个命令行工具：

| 工具 | 作用 |
|---|---|
| `aapt2` | 编译资源、链接出未签名的 APK |
| `javac` | 编译 Java 源码（需要 JDK 17+） |
| `d8` | .class → classes.dex |
| `zipalign` + `apksigner` | 对齐与签名 |

## 1. 准备工具链

```powershell
powershell -ExecutionPolicy Bypass -File build\setup-toolchain.ps1
```

它会下载并解压到 `buildRoot`（默认 `C:\dsh-apk-build`）：

- Temurin JDK 17（约 180 MB）
- Android build-tools r35（约 60 MB）
- platform android-35 的 `android.jar`（约 64 MB）

国内下载慢可以换镜像：

```powershell
powershell -ExecutionPolicy Bypass -File build\setup-toolchain.ps1 `
  -JdkUrl "https://mirrors.tuna.tsinghua.edu.cn/Adoptium/17/jdk/x64/windows/OpenJDK17U-jdk_x64_windows_hotspot_17.0.20.1_1.zip"
```

> **路径必须是纯 ASCII**。`aapt2` 在 Windows 上打不开含中文的路径，所以构建产物放在
> `C:\dsh-apk-build` 这类目录；仓库本身可以放在任意位置。

## 2. 构建

```powershell
powershell -ExecutionPolicy Bypass -File build\build-apk.ps1
```

流程：

1. 把 `android/` 复制到 `<buildRoot>\src`（ASCII 路径）
2. 从 `config/settings.json` 的 `host` 生成 `AppConfig.java`（写死 `https://<host>/`）
3. `aapt2 compile` + `link`（manifest + mipmap 图标）
4. `javac` → `jar` → `d8` 出 `classes.dex`
5. 用 .NET 的 ZipArchive 把 `classes.dex` 塞进 APK
6. `zipalign -f 4` → `apksigner sign`

产物：`dist\DSH-Mobile.apk`。

## 3. 安装

```powershell
adb install -r dist\DSH-Mobile.apk
```

- 首次构建会自动生成签名密钥到 `keystorePath`（默认 `C:\dsh-apk-build\dsh-mobile.keystore`）。
- **密钥丢了就没法覆盖安装**（签名不一致必须卸载重装，登录状态也会丢）。建议备份。
- 想换包名/版本：改 `android/AndroidManifest.xml` 里的 `package`、`versionCode`、`versionName`。

## 4. 换图标

1. 用你自己的 512×512 PNG 覆盖 `proxy/icons/icon-512.png`
2. 同步 `proxy/icons/icon-192.png`、`maskable-512.png`（PWA 用）
3. 重新生成 Android 各密度：

```powershell
python android\make-icons.py
```

需要 Pillow（`pip install pillow`）。也可直接换 `android/res/mipmap-*/ic_launcher.png`。

> 发布衍生作品时请使用自己的图形，不要直接分发他人商标（包括 DeepSeek 的 logo）。

## 5. 改行为

| 想改什么 | 改哪里 |
|---|---|
| 目标地址 | `config/settings.json` 的 `host`（重新构建即可） |
| WebView 设置、UA、登录弹窗 | `android/src/com/deepseek/harness/mobile/MainActivity.java` |
| 应用名 / 主题 / 权限 | `android/AndroidManifest.xml` |
| 最低 Android 版本 | 同上 `uses-sdk` 的 `minSdkVersion`（同时改 `d8 --min-api`） |
