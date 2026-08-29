#!/usr/bin/env node
// System Looting — WebSocket -> TCP/UDP proxy for the Luanti WASM client.
// Implements the webshims emsocket proxy protocol:
//   client: "PROXY IPV4 TCP <ip> <port>" | "PROXY IPV4 UDP <ip> <port>"
//   server: "PROXY OK", then binary frames = raw stream (TCP) or datagrams (UDP).
const { WebSocketServer } = require('ws');
const net = require('net');
const dgram = require('dgram');

const PORT = parseInt(process.env.PROXY_PORT || '8081', 10);
const HOST = '0.0.0.0';

const wss = new WebSocketServer({ port: PORT, host: HOST });

function fail(ws, msg) {
  try { ws.send(msg); } catch (_) {}
  try { ws.close(); } catch (_) {}
}

wss.on('connection', (ws) => {
  ws.binaryType = 'arraybuffer';
  let upstream = null;      // net.Socket or dgram.Socket
  let udpTarget = null;     // {address, port}
  let handshakeDone = false;

  const teardown = () => {
    if (upstream) { try { upstream.destroy ? upstream.destroy() : upstream.close(); } catch (_) {} upstream = null; }
  };
  ws.on('close', teardown);
  ws.on('error', teardown);

  ws.on('message', (data, isBinary) => {
    if (!isBinary) {
      // Control text: PROXY IPV4 TCP|UDP <ip> <port>
      const text = data.toString();
      if (handshakeDone) return;
      const m = text.match(/^PROXY IPV4 (TCP|UDP) (\S+) (\d+)$/);
      if (!m) return fail(ws, 'BAD REQUEST');
      const [, proto, ip, portStr] = m;
      const port = parseInt(portStr, 10);
      if (!port || port < 1 || port > 65535) return fail(ws, 'BAD REQUEST');

      if (proto === 'TCP') {
        const sock = net.connect(port, ip);
        upstream = sock;
        sock.on('connect', () => { handshakeDone = true; ws.send('PROXY OK'); });
        sock.on('data', (chunk) => { if (ws.readyState === ws.OPEN) ws.send(chunk); });
        sock.on('error', (err) => fail(ws, 'CONNECT FAIL: ' + err.message));
        sock.on('close', () => { try { ws.close(); } catch (_) {} });
      } else {
        const sock = dgram.createSocket('udp4');
        upstream = sock;
        udpTarget = { address: ip, port };
        sock.on('message', (msg) => { if (ws.readyState === ws.OPEN) ws.send(msg); });
        sock.on('error', (err) => fail(ws, 'UDP FAIL: ' + err.message));
        handshakeDone = true;
        ws.send('PROXY OK');
      }
      return;
    }
    // Binary frame
    if (!handshakeDone) return;
    const buf = Buffer.from(data);
    if (udpTarget && upstream) {
      upstream.send(buf, udpTarget.port, udpTarget.address);
    } else if (upstream && upstream.write) {
      upstream.write(buf);
    }
  });
});

console.log(`[mtproxy] webshims-compatible proxy listening on ${HOST}:${PORT}`);
