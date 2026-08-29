#!/usr/bin/env node
// All-in-one: serves the System Looting web client (static files) AND the
// webshims WebSocket->TCP/UDP proxy on a SINGLE port.
// Used by: Hugging Face Spaces (only port 7860 is exposed), or anywhere you
// want one-port deployment. WS upgrade requests -> proxy; everything else -> static.
const http = require('http');
const fs = require('fs');
const path = require('path');
const net = require('net');
const dgram = require('dgram');
const { WebSocketServer } = require('ws');

const ROOT = process.env.WWW_ROOT || '/app/pages';
const PORT = parseInt(process.env.PORT || '8080', 10);
const HOST = '0.0.0.0';

const MIME = {
  '.html': 'text/html; charset=utf-8', '.js': 'text/javascript; charset=utf-8',
  '.mjs': 'text/javascript; charset=utf-8', '.wasm': 'application/wasm',
  '.pack': 'application/octet-stream', '.zst': 'application/octet-stream',
  '.png': 'image/png', '.jpg': 'image/jpeg', '.json': 'application/json',
  '.txt': 'text/plain; charset=utf-8',
};

const server = http.createServer((req, res) => {
  let urlPath = decodeURIComponent((req.url || '/').split('?')[0]);
  if (urlPath === '/') urlPath = '/index.html';
  const filePath = path.join(ROOT, path.normalize(urlPath));
  if (!filePath.startsWith(ROOT)) { res.writeHead(403); return res.end('forbidden'); }
  fs.stat(filePath, (err, st) => {
    if (err || !st.isFile()) { res.writeHead(404); return res.end('not found'); }
    res.writeHead(200, {
      'Content-Type': MIME[path.extname(filePath).toLowerCase()] || 'application/octet-stream',
      'Content-Length': st.size, 'Accept-Ranges': 'bytes', 'Cache-Control': 'no-cache',
    });
    fs.createReadStream(filePath).pipe(res);
  });
});

// --- webshims proxy on the same port ---
const wss = new WebSocketServer({ server });
function fail(ws, msg) { try { ws.send(msg); } catch (_) {} try { ws.close(); } catch (_) {} }
wss.on('connection', (ws) => {
  ws.binaryType = 'arraybuffer';
  let upstream = null, udpTarget = null, handshakeDone = false;
  const teardown = () => { if (upstream) { try { upstream.destroy ? upstream.destroy() : upstream.close(); } catch (_) {} upstream = null; } };
  ws.on('close', teardown);
  ws.on('error', teardown);
  ws.on('message', (data, isBinary) => {
    if (!isBinary) {
      if (handshakeDone) return;
      const m = data.toString().match(/^PROXY IPV4 (TCP|UDP) (\S+) (\d+)$/);
      if (!m) return fail(ws, 'BAD REQUEST');
      const [, proto, ip, portStr] = m;
      const port = parseInt(portStr, 10);
      if (!port || port < 1 || port > 65535) return fail(ws, 'BAD REQUEST');
      if (proto === 'TCP') {
        const sock = net.connect(port, ip);
        upstream = sock;
        sock.on('connect', () => { handshakeDone = true; ws.send('PROXY OK'); });
        sock.on('data', (c) => { if (ws.readyState === ws.OPEN) ws.send(c); });
        sock.on('error', (e) => fail(ws, 'CONNECT FAIL: ' + e.message));
        sock.on('close', () => { try { ws.close(); } catch (_) {} });
      } else {
        const sock = dgram.createSocket('udp4');
        upstream = sock; udpTarget = { address: ip, port };
        sock.on('message', (m) => { if (ws.readyState === ws.OPEN) ws.send(m); });
        sock.on('error', (e) => fail(ws, 'UDP FAIL: ' + e.message));
        handshakeDone = true; ws.send('PROXY OK');
      }
      return;
    }
    if (!handshakeDone) return;
    const buf = Buffer.from(data);
    if (udpTarget && upstream) upstream.send(buf, udpTarget.port, udpTarget.address);
    else if (upstream && upstream.write) upstream.write(buf);
  });
});

server.listen(PORT, HOST, () => console.log(`[allinone] client+proxy serving on ${HOST}:${PORT}`));
