# dsh-mobile

[![build](https://github.com/tirckman/dsh-mobile/actions/workflows/build.yml/badge.svg)](https://github.com/tirckman/dsh-mobile/actions/workflows/build.yml)
[![license](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

把桌面端的 **DeepSeek Harness** 变成手机上的 App：Tailscale 内网直连、WebView 原生外壳、开机自启、断线自恢复。

> 非官方项目，与 DeepSeek 官方无关。它是你自己电脑上 dsh 的一个客户端外壳。

```
┌─────────────┐   WireGuard     ┌──────────────────────────────┐
│ 手机 App    │ ──────────────▶ │ https://<host>.<tailnet>.ts.net│
│ (WebView)   │   tailnet only  └──────────────┬───────────────┘
└─────────────┘                                │ tailscale serve (TLS)
                                               ▼
                                  127.0.0.1:3082  pwa-proxy.js
                                  （补 manifest/图标/SW、转发、APK 下载）
                                               ▼
                                  127.0.0.1:3081  dsh web
                                  （真正的 agent host，只绑回环）
                                               ▲
                                  start-stack.ps1 守护 + 开机自启
```

## 它为什么长这样

dsh 桌面版的 Web 服务固定绑定 `127.0.0.1` 并带一次性启动 token，手机无法直连。官方的对外方式是用 `dsh --profile web --host ... --public-url ...` 另起一个 Web 实例，再放到可信入口后面。这个项目就是把这套做法封装成"打开就能用"：

1. **Tailscale 提供加密选址**：`tailscale serve` 把 `https://<你的机器>.ts.net` 反代到本机回环，只有你 tailnet 里的设备能访问，不暴露公网，也不用开防火墙。
2. **PWA 外壳代理**：dsh 自带的 manifest 只有 SVG 图标、没有 service worker，Chrome 不会给"安装应用"入口；代理补上 PNG 图标 + 空 fetch 的 SW + `<link rel="manifest">`，其余请求原样转发（保留 Host，dsh 的信任校验才能过）。
3. **APK 是可选的原生壳**：约 200 行 WebView，解决"想要一个真正的 App 图标/独立窗口"的需求，不依赖浏览器。用标准 Android 工具链直接构建，不需要 Android Studio。
4. **守护进程 + 开机自启**：dsh web 或代理挂了会自动拉起；Tailscale Serve 路由丢了会自动补。

## 特性

- ✅ 不暴露公网：端口只绑 `127.0.0.1`，`tailscale serve` 默认仅 tailnet
- ✅ 免重复登录：认证 cookie 由持久密钥签名，重启 dsh、重装 App 都不会失效（30 天）
- ✅ 断线兜底：连不上时显示"Retry"页而不是白屏
- ✅ 进程守护 + 登录自启（Windows 启动文件夹，隐藏窗口，不需要管理员）
- ✅ 三种接入方式：Tailscale（远程）/ 同 Wi-Fi 局域网 / USB 数据线（`adb reverse`）
- ✅ 只用官方命令行工具构建 APK，不依赖 Gradle / Android Studio

## 快速开始（Windows）

前置：Windows 10/11、[DeepSeek Harness 桌面版](https://github.com/deepseek-ai/deepseek-harness)、[Tailscale](https://tailscale.com/)（电脑和手机登录同一账号）。

**1. 克隆并配置**

```powershell
git clone https://github.com/<you>/dsh-mobile.git
cd dsh-mobile
copy config\settings.example.json config\settings.json
notepad config\settings.json      # 把 host 改成你的机器名，见第 2 步
```

**2. 拿到你的 tailnet 主机名**

```powershell
& "C:\Program Files\Tailscale\tailscale.exe" status --json
# 找 Self.DNSName，例如 desktop-abc123.tailxxxx.ts.net
```

**3. 启用 Tailscale Serve（只需一次）**

```powershell
& "C:\Program Files\Tailscale\tailscale.exe" serve --bg --https=443 http://127.0.0.1:3082
```

如果提示 *Serve is not enabled on your tailnet*，打开它给出的 `https://login.tailscale.com/f/serve?node=...` 授权一次。

**4. 构建并安装 APK**

```powershell
powershell -ExecutionPolicy Bypass -File build\setup-toolchain.ps1   # 首次：下载 JDK + build-tools + android.jar
powershell -ExecutionPolicy Bypass -File build\build-apk.ps1         # 产出 dist\DSH-Mobile.apk
adb install -r dist\DSH-Mobile.apk
```

（不想装 APK 也行：用手机 Chrome 打开 `https://<host>/`，登录后菜单里"安装应用"即可装成 PWA。）

**可选：让 CI 帮你构建 APK**

仓库自带 GitHub Actions（Windows runner）。Fork 之后在 *Settings → Variables* 里加一个
`DEFAULT_HOST` = 你的主机名，之后每次 push 都会自动构建并上传 `DSH-Mobile-apk` 产物；也可以用
*Actions → build → Run workflow* 临时指定 host。想要固定签名，再加一个
`ANDROID_KEYSTORE_BASE64` secret。细节见 [docs/android-build.md](docs/android-build.md#用-github-actions-构建)。

**5. 装开机自启**

```powershell
scripts\install-autostart.cmd
```

之后开机 → 手机点桌面上的 **DSH** 图标即可。

**首次登录**：手机 App 打开时会弹"Sign in"，把 `scripts\status.cmd` 打印的带 token 链接复制到手机剪贴板，粘贴进对话框点登录。一次就好。

## 目录结构

```
dsh-mobile/
├── config/settings.example.json   配置模板（复制成 settings.json，后者不入库）
├── proxy/
│   ├── pwa-proxy.js               PWA 外壳 + 反向代理 + APK 下载路由
│   └── icons/                     PWA 图标（自绘，可替换）
├── android/                       APK 源码与资源
│   ├── AndroidManifest.xml
│   ├── src/.../MainActivity.java  WebView 壳
│   ├── src/.../AppConfig.java.template  构建时注入你的 host
│   ├── res/mipmap-*/              启动图标
│   └── make-icons.py              重生成图标（Pillow）
├── build/
│   ├── setup-toolchain.ps1        下载 JDK/build-tools/platform
│   └── build-apk.ps1              aapt2 + javac + d8 + apksigner 全流程
├── scripts/
│   ├── start-stack.ps1            守护进程（自启入口）
│   ├── install-autostart.ps1      装启动项
│   ├── uninstall-autostart.ps1    卸载启动项
│   ├── status.ps1                 状态自检（端口/serve/登录链接）
│   ├── fix-phone-vpn.ps1          手机端 VPN 保活（adb）
│   ├── lan-mode.ps1               同 Wi-Fi 模式
│   └── usb-mode.ps1               USB 模式
└── docs/                          详细文档
```

## 配置项

`config/settings.json`（不入库）里的关键字段：

| 字段 | 说明 |
|---|---|
| `host` | Tailscale MagicDNS 名或局域网地址，APK 会把它编进去 |
| `webPort` / `pwaPort` / `servePort` | 回环端口与对外 HTTPS 端口，默认 3081 / 3082 / 443 |
| `dshCli` | dsh CLI 路径（桌面版自带：`%LOCALAPPDATA%\Programs\DeepSeek Harness\resources\runtime\cli\bin\dsh.cmd`） |
| `nodeExe` | Node 可执行文件（桌面版自带的那份即可） |
| `buildRoot` | APK 构建目录，**必须是纯 ASCII 路径**（aapt2 不支持非 ASCII 路径） |
| `keystorePath` / `keystorePass` | 签名密钥；重装必须用同一个 |

所有字段都可以用环境变量覆盖，例如 `DSH_MOBILE_HOST`、`DSH_MOBILE_WEB_PORT`。

## 隐私与安全

- 仓库里**不含**任何个人标识：主机名、IP、路径、token、密钥都在 `config/settings.json`（已 gitignore）。
- App 与网页之间只有 HTTPS（`tailscale serve` 用 `*.ts.net` 证书），且 `usesCleartextTraffic=false`。
- 登录 token 是**操作你电脑的凭证**，等同于网页端的会话；别贴到公开地方。
- `tailscale serve` 默认只在 tailnet 内可达。**不要**改用 `tailscale funnel`（那会暴露到公网）。
- 图标是本项目自绘的 "DSH" 字样，不包含 DeepSeek 官方 logo。

安全问题请走仓库的 **Security → Report a vulnerability**，范围与威胁模型见 [SECURITY.md](SECURITY.md)。

## 已知限制

- 脚本目前只支持 **Windows**（PowerShell/cmd）。服务端思路可以平移到 macOS/Linux，需要自己改。
- 手机端只在 MIUI/HyperOS（Android 16）实测过；其他 ROM 的电量策略需要对应调整。
- 最低 Android 7.0（API 24）。
- 同一份会话不要在手机和电脑上**同时**操作（两个客户端挂同一个 session 会互相干扰），手机上建议新开会话。

## 文档

- [docs/setup-tailscale.md](docs/setup-tailscale.md) — Tailscale / Serve 配置与验证
- [docs/android-build.md](docs/android-build.md) — APK 工具链、构建、签名、换图标
- [docs/phone-settings.md](docs/phone-settings.md) — 让 VPN 在手机上活得久（Always-on、电量策略）
- [docs/troubleshooting.md](docs/troubleshooting.md) — 401/403/乱码/连不上等排查

## English

An unofficial mobile client for [DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness): it runs `dsh --profile web` on loopback, exposes it to your tailnet through `tailscale serve`, adds a tiny PWA-shell proxy (so the GUI is installable), and optionally wraps it in a ~200-line WebView APK. Windows scripts for autostart/supervision; the APK builds with plain `aapt2`/`d8`/`apksigner` (no Gradle).

## License

MIT — see [LICENSE](LICENSE).
