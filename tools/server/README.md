# WebSocket → TCP/UDP bridge for the System Looting WASM client

`websocket_proxy.js` — a self-contained Node server implementing the
[webshims](https://github.com/paradust7/webshims) emsocket proxy protocol,
so browser players (the WASM web build) can connect to your dedicated
Luanti server. It replaces the public dustlabs.io proxies
(`wss://luanti.dustlabs.io/proxy`) with one you control.

## Protocol (implemented here)

1. Client opens a WebSocket to the proxy.
2. Client sends `PROXY IPV4 TCP <ip> <port>` (or `UDP`).
3. Proxy connects and replies `PROXY OK`.
4. Binary WebSocket frames are relayed: TCP stream, or UDP datagrams.

## Run

```bash
npm install ws
node websocket_proxy.js            # PROXY_PORT=8081 PROXY_HOST=0.0.0.0 (defaults)
```

## Point the web client at it

In the built web client (see `docs/DEPLOY_SERVER.md` §7):

- `launcher.js`: `this.proxyUrl = "wss://your-proxy.example/proxy"`
- `index.html`: add `[ "wss://your-proxy.example", "label" ]` to the proxy
  dropdown list.

## Verify

```bash
node -e "const W=require('ws');const w=new W('ws://localhost:8081');
w.on('open',()=>w.send('PROXY IPV4 TCP 127.0.0.1 30000'));
w.on('message',d=>console.log(d.toString()));"   # → PROXY OK
```
