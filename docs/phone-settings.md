# 手机侧设置：让 VPN 活得久

**这是最容易踩的坑**：插着 USB（充电）时一切正常，一拔线手机上的 Tailscale 就被系统杀掉，App 立刻连不上。电脑端完全正常，问题在手机。

## 用 adb 一键设置

手机插 USB、开启"开发者选项 → USB 调试"后：

```powershell
powershell -ExecutionPolicy Bypass -File scripts\fix-phone-vpn.ps1
```

它做四件事：

| 设置 | 作用 |
|---|---|
| `always_on_vpn_app = com.tailscale.ipn` | 开机自动连 VPN；VPN 进程被杀后系统会重新拉起 |
| `always_on_vpn_lockdown = 0` | 断线时不锁死网络（避免没网络可用） |
| Doze 白名单 | 电量优化不冻结它 |
| `RUN_IN_BACKGROUND` / `RUN_ANY_IN_BACKGROUND` = allow | 允许后台运行 |

注意：`adb install` 不需要 root，但这些是 `settings put secure`，在部分定制 ROM 上可能被拒。

## 仍需要手动点的两项

Android/MIUI 没有把这两项暴露给 adb：

1. **设置 → 应用设置 → 应用管理 → Tailscale → 省电策略 → 无限制**
2. **同一页面 → 自启动 → 允许**（MIUI/HyperOS 专有）
3. （可选）任务切换界面把 Tailscale 卡片上锁

## 验证是否真的解决

1. 拔掉 USB
2. 等 1 分钟，在电脑上跑：

```powershell
& "C:\Program Files\Tailscale\tailscale.exe" status
```

手机那行应该保持 `active` / `idle`，而不是 `offline, last seen ...`。

没解决的话：用手机实际打开一次 Tailscale App，看它是否显示 connected；如果显示未连接，就是被杀了。

## 另一种选择：PWA（不需要 APK）

手机 Chrome 打开 `https://<host>/`，登录后菜单 → **安装应用 / 添加到主屏幕**。PWA 同样依赖 Tailscale，所以上面的保活设置一样要做。

## iPhone

iOS 上 Tailscale 可以用"按需连接（On-Demand）"，在 Tailscale 设置里打开即可；PWA 用 Safari 的"添加到主屏幕"。
