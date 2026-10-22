# Tailscale 与 Serve 配置

## 1. 装好 Tailscale，确认两端在同一 tailnet

电脑和手机都登录**同一个账号**，然后：

```powershell
& "C:\Program Files\Tailscale\tailscale.exe" status
```

```
100.x.y.z    desktop-abc123      you@example.com  windows  -
100.a.b.c    your-phone          you@example.com  android  active; direct ...
```

- 第二列是设备名，后面 `status --json` 里的 `Self.DNSName` 就是 `<设备名>.<tailnet>.ts.net`
- 手机那行如果没有 `active`，先在手机上打开 Tailscale 并连接

## 2. 启用 HTTPS 证书 / Serve

Serve 需要 tailnet 开启 HTTPS（一次性）：

```powershell
& "C:\Program Files\Tailscale\tailscale.exe" serve --bg --https=443 http://127.0.0.1:3082
```

首次可能返回：

```
Serve is not enabled on your tailnet.
To enable, visit:
    https://login.tailscale.com/f/serve?node=xxxxx
```

用浏览器打开该链接批准一次（需要 tailnet 管理员，通常就是你），再执行上面的命令，应输出：

```
Available within your tailnet:
https://desktop-abc123.tailxxxx.ts.net/
|-- proxy http://127.0.0.1:3082
```

复查：

```powershell
& "C:\Program Files\Tailscale\tailscale.exe" serve status
```

> `serve` 的配置由 tailscaled 服务持久化，重启电脑后依然生效。`scripts/start-stack.ps1`
> 还会每 10 秒检查一次，配置丢了自动补。

## 3. 验证

在电脑上（不需要开 dsh）先确认 TLS 与解析都通：

```powershell
curl.exe -s -o NUL -w "%{http_code}`n" https://<host>/
```

- 返回 `502`：Serve 通了，但后面 3082 没有服务（正常，先启动 dsh 和代理）
- 返回 `401`：链路完整，只差登录 cookie ✅
- 卡住/超时：检查 Tailscale 是否连接、MagicDNS 是否开启

## 4. 常见调整

| 想做什么 | 做法 |
|---|---|
| 换端口 | 把 `servePort` 改成别的（比如 8443），重新跑 `serve --https=<port>` |
| 关掉路由 | `tailscale serve --https=443 off` |
| 只想局域网 | 不用 Tailscale，见 `scripts/lan-mode.ps1` |
| 只想插线用 | 见 `scripts/usb-mode.ps1`（`adb reverse`） |

## 安全提醒

- **不要**用 `tailscale funnel`：它会把站点暴露到公网。
- Serve 的访问控制依赖 tailnet 成员身份，确保 tailnet 里没有你不想授权的设备。
- dsh 的启动链接是完整凭证，等同于电脑上的操作权限。
