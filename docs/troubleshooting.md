# 排错

先跑一次自检，它会告诉你链路断在哪一层：

```powershell
scripts\status.cmd
```

## 症状 → 原因

### App/网页打不开，提示 "Cannot reach the desktop"

手机没连上 VPN（最常见）。打开手机上的 Tailscale 确认已连接，然后点 Retry。

如果一直连不上，在电脑上确认：

```powershell
& "C:\Program Files\Tailscale\tailscale.exe" status   # 手机是否 active
& "C:\Program Files\Tailscale\tailscale.exe" serve status  # 是否指向 127.0.0.1:3082
Get-NetTCPConnection -LocalPort 3081,3082 -State Listen  # 两个端口是否在听
```

### 页面显示 `dsh web authentication required`

不是坏了，是认证 cookie 没带上：

- **首次使用**：App 里正常会弹登录框，粘贴带 token 的链接即可。
- **用浏览器**：从外部（扫码/点链接/`am start`）打开带 token 的地址时，Chrome 会把这次导航判为 cross-site，而 cookie 是 `SameSite=Strict`，于是跳转后不带 cookie。**点一下地址栏再回车**（或刷新一次）就进去了。

### `403` / 打开是白页

Host/Origin 校验没过。dsh 只信任「绑定的地址」和 `--trusted-host` 里列出的 host。用 Tailscale 时要保证：

- `--public-url https://<host>/` 和 `--trusted-host <host>` 与浏览器实际访问的域名**完全一致**
- 通过反向代理访问时，代理要保留 `Host`（本项目的 `pwa-proxy.js` 就是原样转发 Host）

### 网页内容变成乱码

代理转发时没有去掉 `accept-encoding`，把 gzip 后的字节当成 UTF-8 注入 HTML。本项目已处理（转发前删除该头）。如果你自己改了代理，注意这一点。

### `aapt2 compile failed: failed to open directory`

构建路径含非 ASCII 字符（中文用户名最常见）。把 `buildRoot` 指到 `C:\dsh-apk-build` 这类纯英文路径。

### `javac: illegal character: '\ufeff'`

生成的 `AppConfig.java` 带了 BOM（PowerShell 5.1 的 `Set-Content -Encoding UTF8` 默认写 BOM）。本项目用 `UTF8Encoding($false)` 写文件；如果你改了构建脚本，注意这一点。

### `tailscale serve` 报 "Serve is not enabled on your tailnet"

打开它给出的 `https://login.tailscale.com/f/serve?node=...` 授权一次，再重跑命令。

### 手机 App 里点开会话显示"任务已停止"

说明两个客户端挂了同一个会话，或者 host 在会话进行中被重启。手机上尽量新开会话；已经停止的那一轮只能回电脑端继续。

### USB（adb）时有时无

和数据线/接口有关，和本项目无关（App 走 Tailscale，不依赖 USB）。换线或换口；`adb kill-server` 后重试。

## 日志位置

```
%LOCALAPPDATA%\dsh-mobile\logs\
├── supervisor.log   守护进程的记录（启动、重启、token）
├── web.out.log      dsh web 的输出（含带 token 的启动链接）
├── web.err.log      dsh web 的错误
├── proxy.out.log    代理输出
├── proxy.app.log    代理的请求日志
└── last-token.txt   最近一次的带 token 链接
```

## 彻底重来

```powershell
scripts\uninstall-autostart.cmd
& "C:\Program Files\Tailscale\tailscale.exe" serve --https=443 off
# 必要时清掉日志和配置
Remove-Item -Recurse "$env:LOCALAPPDATA\dsh-mobile"
```
