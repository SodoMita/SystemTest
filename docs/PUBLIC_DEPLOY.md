# Making a System Looting server PUBLIC (joinable from the internet)

Local servers (`localhost:30000`, LAN IPs) are trivial. This doc is about the
two things that make a server **public**:

1. A reachable public address (players from anywhere can join).
2. (Optional) Presence in the Luanti in-game server list.

A public server must run on a machine **you keep online** — a VPS, or your own
PC with the port opened. Free sandbox/CI machines cannot host one permanently:
they have no public UDP port and are wiped regularly. Pick one path below —
total time ~10 minutes.

---

## Important: Luanti speaks UDP

The Luanti game protocol is **UDP-only** (port 30000 by default). This rules
out most HTTP-style tunnels:

| Tool | UDP | Account | Verdict |
|---|---|---|---|
| **playit.gg** | ✅ | free account | **best for this** — built for game servers, free TCP+UDP tunnels, CGNAT bypass |
| port forwarding (own router) | ✅ | none | ideal if your ISP gives you a public IPv4 |
| Cloudflare Tunnel / trycloudflare | ❌ | none | won't work for native clients |
| ngrok | ❌ | free token | won't work for native clients |
| pinggy / localtonet | ✅ | free account | alternatives; shorter free sessions |

The WASM web build is the only client that connects over TCP/WebSocket (via a
proxy), so web play and native play are two separate paths (see §5).

---

## Path A — playit.gg tunnel (free, works behind CGNAT, UDP)

1. Run the Luanti server locally exactly as in `DEPLOY_SERVER.md` (any host,
   any port — `localhost:30000` is fine; playit does the public exposure).
2. Install the playit agent (Linux):

   ```bash
   curl -SsL https://playit.gg/download/playit-linux-amd64 -o playit && chmod +x playit
   # or: https://github.com/playit-cloud/playit-agent/releases
   ```

3. `./playit` → it prints a **claim link** (https://playit.gg/claim/…) — open
   it once, create the free account, and the agent is bound to you.
4. In the agent TUI / web dashboard add a tunnel:
   - **Type:** UDP (or "custom"), **Port:** 30000, protocol UDP.
   - (Also add TCP 30000 if you want server-list pings.)
5. playit gives you a public address like `123.45.67.89:51234`. Any Luanti
   client can now join **that address** — no router config, works behind CGNAT.
6. To also appear in the **in-game server list**, set in `systemloot.conf`:

   ```ini
   server_announce = true
   server_name = System Looting — Public
   server_description = Competitive team survival. Join!
   ```

   > `server_address` (domain only, no port) is only for when you have a real
   > domain. Behind a tunnel the list may not detect the right IP — the playit
   > address is the reliable join path regardless.

7. Keep it alive: run the server and agent under `systemd` (below) or
   `screen`/`tmux`.

---

## Path B — VPS with a public IP (most reliable)

Any $3–6/mo VPS (Hetzner, DigitalOcean, Vultr, Timeweb Cloud, …) with Debian
12 / Ubuntu 24.04:

```bash
# 1. engine (Debian 12 ships luanti-server; or the prebuilt
#    ROllerozxa/luantiserver binary, or build from source — DEPLOY_SERVER.md §1)
sudo apt update && sudo apt install -y luanti-server    # or: minetest-server

# 2. game
sudo mkdir -p /srv/systemloot/games
sudo ln -s /path/to/SystemTest /srv/systemloot/games/SystemTest
#    (copy the repo to the VPS: git clone https://github.com/SodoMita/SystemTest)

# 3. world + config
sudo mkdir -p /srv/systemloot/worlds/systemloot
printf 'gameid = SystemTest\nbackend = sqlite3\nmg_name = singlenode\n' \
  | sudo tee /srv/systemloot/worlds/systemloot/world.mt
#    …write systemloot.conf as in DEPLOY_SERVER.md §4 with:
#    server_announce = true, server_name, server_description

# 4. firewall: open the port (TCP+UDP)
sudo ufw allow 30000/tcp && sudo ufw allow 30000/udp

# 5. systemd unit (DEPLOY_SERVER.md §5) → systemctl enable --now systemloot
```

On a VPS the IP is already public — no tunnel needed. Players join
`<vps-ip>:30000`, and with `server_announce = true` (engine with cURL) the
server appears in the Luanti server list within ~a minute.

---

## Path C — home PC with port forwarding

If your ISP gives you a public IPv4 (check https://ipv4.icanhazip.com matches
your router's WAN IP — if not, you're behind CGNAT and MUST use Path A):

1. Router admin → Port Forwarding → forward **UDP 30000** (and TCP 30000)
   to the PC's LAN IP.
2. `sudo ufw allow 30000/udp` (or your firewall) on the PC.
3. Run the server; players join `<your-public-ip>:30000`.
4. Consider a dynamic-DNS name (duckdns.org etc.) and set `server_address`.

---

## §5 Web (browser) players

Native and web clients both join the *same* server — but the browser client
cannot do raw UDP, so it goes through a WebSocket→TCP bridge:

- The official web build's launcher defaults to the public dustlabs proxies
  (`wss://luanti.dustlabs.io/proxy`), which can reach any *public* server —
  so browser players can already join your playit/VPS server by address.
- To self-host the bridge, this repo ships `tools/server/websocket_proxy.js`:

  ```bash
  cd tools/server && npm install ws
  node websocket_proxy.js        # PROXY_PORT=8081, serves PROXY IPV4 TCP|UDP
  ```

  and patch the web client's `launcher.js` `this.proxyUrl` (or add an entry
  to the dropdown in `index.html`) to point at it.

---

## Verification checklist (from a DIFFERENT machine/network)

```bash
# TCP reachability (server-list ping + web proxy path)
nc -vz <public-address> 30000
# UDP reachability — join with a Luanti client
# (Join Server → <address> → watch for the handshake)
```

Then check the server list: Luanti client → Join Game → search your
`server_name`. If the server is announced, its status shows Online.

## Keep it running

systemd unit (DEPLOY_SERVER.md §5) or:

```bash
# playit agent under systemd
sudo tee /etc/systemd/system/playit.service >/dev/null <<'EOF'
[Unit]
Description=playit.gg tunnel
After=network-online.target

[Service]
WorkingDirectory=/srv/systemloot
ExecStart=/srv/systemloot/playit
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF
sudo systemctl enable --now playit
```
