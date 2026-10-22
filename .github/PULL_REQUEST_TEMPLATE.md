## What this changes

<!-- one or two sentences -->

## Why

<!-- the problem it solves; link an issue if there is one -->

## How I tested it

<!-- e.g. built the APK on Windows 11 + JDK 17, installed on Android 16, signed in, sent a message -->

- [ ] `node --check proxy/pwa-proxy.js` passes
- [ ] `build\build-apk.ps1` runs and produces `dist/DSH-Mobile.apk`
- [ ] `scripts\status.ps1` reports expected state (if scripts changed)

## Checklist

- [ ] No personal data in the diff (hostnames, IPs, tokens, local paths, keystores, APKs)
- [ ] Build paths stay ASCII (`aapt2` cannot handle non-ASCII paths on Windows)
- [ ] Docs updated if behaviour or configuration changed
- [ ] Commits are focused; unrelated formatting changes are avoided
