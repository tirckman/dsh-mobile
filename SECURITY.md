# Security policy

## Supported versions

Only the `main` branch is supported. This is a small, personal-use tool; there are no LTS branches.

## Reporting a vulnerability

Please use GitHub's **private vulnerability reporting**: go to the repository's *Security* tab →
*Report a vulnerability*. Do not open a public issue for anything that could expose a user's
machine.

If private reporting is unavailable, open a minimal public issue that says only "security issue,
please contact me" — do not include details, logs, or hostnames.

## What this project actually exposes

Understanding the model makes reports much easier to triage:

```
phone app / browser ──TLS(tailnet)──> tailscale serve ──> 127.0.0.1:<pwaPort>  proxy
                                                              └─> 127.0.0.1:<webPort>  dsh web
```

- `dsh web` and the proxy bind **loopback only**. The only network exposure is whatever
  `tailscale serve` publishes, which by default is reachable by devices in the same tailnet.
- Authentication and authorization are **dsh's job**, not the proxy's. The proxy forwards requests
  and injects shell bits (manifest, service worker, icons) into HTML responses. It does not
  implement its own auth, and it does not decide who may reach dsh.
- The tokenized launch URL printed by `dsh web` is a **credential**: anyone holding it can drive the
  agent on that machine. Treat it like a password.

### In scope

- Auth or trust-boundary bypass introduced by this project's code (for example: the proxy allows
  requests that dsh's Host/Origin fence would otherwise reject, or it rewrites headers in a way that
  breaks that fence).
- Injection or request smuggling in `proxy/pwa-proxy.js` (HTML injection paths, header handling,
  upgrade pass-through).
- Path traversal / arbitrary file read or write in the proxy's static routes (`/pwa/*`,
  `/dsh-mobile.apk`).
- Command injection, unsafe quoting, or credential leakage in the PowerShell scripts, including the
  autostart supervisor and the APK build pipeline.
- Weaknesses in the Android shell (WebView settings that enable unintended navigation, exported
  components, unsafe file handling).
- Secrets accidentally committed to the repository.

### Out of scope

- Vulnerabilities in [DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness) itself.
- Vulnerabilities in Tailscale, Android, or the user's tailnet configuration.
- Exposure caused by deliberately publishing the port publicly, for example `tailscale funnel`,
  a port-forward, or binding the web server to a non-loopback address and forwarding it.
- Anyone with legitimate access to the machine, the tailnet, or the tokenized URL.
- Denial of service against your own single-user desktop.

## Hardening checklist for users

1. **Never** use `tailscale funnel` for this. Keep it `serve` (tailnet-only).
2. Keep `tailnet` membership tight; ACLs can restrict which devices reach port 443 on the host.
3. Do not paste logs publicly: `web.out.log` and `last-token.txt` contain the launch token. Redact
   `?token=...` before sharing.
4. Keep `config/settings.json`, the signing keystore, and `.logs` out of git (already gitignored).
5. The APK is signed with your own key; if you publish builds, publish them from your own CI with
   your own secret, never a shared key.
6. Rotate by restarting `dsh web` (new token) if a launch URL leaked. Existing cookies stay valid
   until they expire (30 days), so also clear the app's site data if you need a hard reset.

## Disclosure

Please give a reasonable window (a few weeks) before public disclosure. Credit is given in the
release notes unless you prefer otherwise.
