// dsh-mobile PWA shell proxy
//
//   tailscale serve (https://<host>) -> 127.0.0.1:<pwaPort> (this process) -> 127.0.0.1:<webPort> (dsh web)
//
// Why: the dsh web app ships a manifest with only an SVG icon and no service worker, so Chrome
// will not offer to install it as an app. This proxy adds PNG icons, a no-op service worker and
// a <link rel="manifest"> tag, and forwards everything else untouched (Host header preserved so
// dsh's browser-trust fence still accepts the tailnet hostname).
//
// Env:
//   DSH_MOBILE_PWA_PORT   listen port            (default 3082)
//   DSH_MOBILE_WEB_PORT   upstream dsh web port  (default 3081)
//   DSH_MOBILE_APP_NAME   app name in manifest   (default "DeepSeek Harness")
//   DSH_MOBILE_LOG        optional log file path
'use strict';

const http = require('http');
const fs = require('fs');
const path = require('path');

const LISTEN_PORT = Number(process.env.DSH_MOBILE_PWA_PORT || 3082);
const TARGET_PORT = Number(process.env.DSH_MOBILE_WEB_PORT || 3081);
const APP_NAME = process.env.DSH_MOBILE_APP_NAME || 'DeepSeek Harness';
const LOG = process.env.DSH_MOBILE_LOG || '';
const ICON_DIR = path.join(__dirname, 'icons');
const APK_PATH = path.join(__dirname, '..', 'dist', 'DSH-Mobile.apk');

function log(msg) {
  if (!LOG) return;
  try { fs.appendFileSync(LOG, new Date().toISOString() + ' ' + msg + '\n'); } catch {}
}

const MANIFEST = {
  id: '/',
  name: APP_NAME,
  short_name: 'DSH',
  description: APP_NAME + ' mobile',
  start_url: '/',
  scope: '/',
  display: 'standalone',
  display_override: ['standalone', 'fullscreen'],
  orientation: 'any',
  background_color: '#101114',
  theme_color: '#101114',
  icons: [
    { src: '/pwa/icon-192.png', sizes: '192x192', type: 'image/png', purpose: 'any' },
    { src: '/pwa/icon-512.png', sizes: '512x512', type: 'image/png', purpose: 'any' },
    { src: '/pwa/maskable-512.png', sizes: '512x512', type: 'image/png', purpose: 'maskable' },
  ],
};

// No caching: only here to satisfy Chrome's installability check.
const SW = `/* dsh-mobile PWA shell: pass-through only, no caching */
self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', (event) => event.waitUntil(self.clients.claim()));
self.addEventListener('fetch', () => {});
`;

const INJECT = [
  '<link rel="manifest" href="/manifest.webmanifest">',
  '<link rel="apple-touch-icon" href="/pwa/icon-192.png">',
  '<meta name="theme-color" content="#101114">',
  '<meta name="mobile-web-app-capable" content="yes">',
  '<meta name="apple-mobile-web-app-capable" content="yes">',
  '<meta name="apple-mobile-web-app-title" content="DSH">',
  "<script>if('serviceWorker' in navigator){addEventListener('load',function(){navigator.serviceWorker.register('/sw.js',{scope:'/'}).catch(function(){})})}</script>",
].join('');

const ICONS = {
  '/pwa/icon-192.png': 'icon-192.png',
  '/pwa/icon-512.png': 'icon-512.png',
  '/pwa/maskable-512.png': 'maskable-512.png',
};

function sendJSON(res, obj) {
  const body = Buffer.from(JSON.stringify(obj));
  res.writeHead(200, {
    'content-type': 'application/manifest+json; charset=utf-8',
    'content-length': body.length,
    'cache-control': 'no-cache',
  });
  res.end(body);
}

function sendFile(res, file, type) {
  fs.readFile(file, (err, buf) => {
    if (err) { res.writeHead(404); res.end('not found'); return; }
    res.writeHead(200, { 'content-type': type, 'content-length': buf.length, 'cache-control': 'public, max-age=86400' });
    res.end(buf);
  });
}

function proxy(req, res) {
  // Drop accept-encoding: we must see plain HTML to inject the shell bits, and this hop is loopback.
  const headers = Object.assign({}, req.headers, { host: req.headers.host });
  delete headers['accept-encoding'];

  const up = http.request(
    { host: '127.0.0.1', port: TARGET_PORT, method: req.method, path: req.url, headers },
    (pr) => {
      const type = String(pr.headers['content-type'] || '');
      if (type.includes('text/html')) {
        const chunks = [];
        pr.on('data', (c) => chunks.push(c));
        pr.on('end', () => {
          let html = Buffer.concat(chunks).toString('utf8');
          if (html.includes('</head>')) html = html.replace('</head>', INJECT + '</head>');
          else html = INJECT + html;
          const body = Buffer.from(html, 'utf8');
          const outHeaders = Object.assign({}, pr.headers, { 'content-length': body.length });
          delete outHeaders['content-encoding'];
          delete outHeaders['transfer-encoding'];
          res.writeHead(pr.statusCode || 200, outHeaders);
          res.end(body);
        });
        return;
      }
      res.writeHead(pr.statusCode || 200, pr.headers);
      pr.pipe(res);
    }
  );
  up.on('error', (e) => {
    log('ERR ' + e.message);
    try { res.writeHead(502); res.end('upstream error'); } catch {}
  });
  req.pipe(up);
}

const server = http.createServer((req, res) => {
  const url = req.url.split('?')[0];
  log('REQ ' + req.method + ' ' + url);

  if (url === '/manifest.webmanifest' || url === '/manifest.json') return sendJSON(res, MANIFEST);

  if (url === '/sw.js') {
    const body = Buffer.from(SW);
    res.writeHead(200, {
      'content-type': 'application/javascript; charset=utf-8',
      'content-length': body.length,
      'service-worker-allowed': '/',
      'cache-control': 'no-cache',
    });
    return res.end(body);
  }

  if (ICONS[url]) return sendFile(res, path.join(ICON_DIR, ICONS[url]), 'image/png');

  if (url === '/dsh-mobile.apk') {
    return sendFile(res, APK_PATH, 'application/vnd.android.package-archive');
  }

  if (url === '/healthz') {
    return sendJSON(res, { ok: true, upstream: TARGET_PORT, app: APP_NAME });
  }

  return proxy(req, res);
});

// WebSocket / stream upgrade pass-through (dsh uses /api/remote.mux).
server.on('upgrade', (req, socket, head) => {
  log('UPGRADE ' + req.url);
  const headers = Object.assign({}, req.headers);
  const up = http.request({
    host: '127.0.0.1', port: TARGET_PORT, method: req.method, path: req.url, headers, agent: false,
  });
  up.on('upgrade', (pr, upSocket, upHead) => {
    socket.write(
      'HTTP/1.1 101 Switching Protocols\r\n' +
        Object.entries(pr.headers).map(([k, v]) => k + ': ' + v).join('\r\n') +
        '\r\n\r\n'
    );
    if (upHead && upHead.length) socket.write(upHead);
    if (head && head.length) upSocket.write(head);
    upSocket.pipe(socket);
    socket.pipe(upSocket);
    upSocket.on('error', () => socket.destroy());
    socket.on('error', () => upSocket.destroy());
  });
  up.on('error', (e) => { log('ERR upgrade ' + e.message); socket.destroy(); });
  up.end();
});

server.listen(LISTEN_PORT, '127.0.0.1', () => {
  console.log('dsh-mobile proxy listening on 127.0.0.1:' + LISTEN_PORT + ' -> 127.0.0.1:' + TARGET_PORT);
  log('listening ' + LISTEN_PORT + ' -> ' + TARGET_PORT);
});
