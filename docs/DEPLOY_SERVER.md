# Deploying a public System Looting server

**System Looting** is a Luanti (formerly Minetest) game. The repo itself is the
*game* — it is not a server binary. A public server is a **dedicated
`luantiserver` process** running on a machine with a public IP (VPS or port
forwarded home box), with this repo installed as the game.

> The release pipeline (`release.yml`) only ships *clients* (Windows/macOS/Linux
> bundles, Android APKs, and a WASM web build). None of those include a server;
> the workflow comments say so explicitly: *"playing against a dedicated
> SystemTest server requires hosting one separately."* This document is that
> missing piece.

## Architecture

```
                    ┌─────────────────────────────┐
 desktop/Android    │  Luanti engine (client)     │
 clients ─────────► │  connects directly over     │
                    │  UDP/TCP :30000             │
                    └──────────────┬──────────────┘
                                   │  minetest protocol
                    ┌──────────────▼──────────────┐
 WASM web build ──► │  WebSocket proxy            │
 (sodomita.github.io│  (dustlabs.io, or your own  │
 /SystemTest)       │   webshims proxy)           │
                    └──────────────┬──────────────┘
                                   │
                    ┌──────────────▼──────────────┐
                    │  luantiserver + SystemTest   │
                    │  (this document)             │
                    └─────────────────────────────┘
```

Browser clients cannot open raw TCP sockets, so the web build tunnels through a
WebSocket→TCP proxy (default `wss://luanti.dustlabs.io/proxy`, selectable in the
launcher). Native clients connect straight to `host:port`. Either way, **the
server itself is a plain Luanti server** — one process, one port (`30000`,
UDP for server list ping, TCP for the protocol).

## 1. Get the engine

Any recent Luanti server works (game requires engine ≥ 5.0). Pick one:

### A. Distro package (easiest)

```bash
# Debian/Ubuntu
sudo apt install luanti-server        # binary: luantiserver
# older distros may still ship it as:
sudo apt install minetest-server      # binary: minetestserver
```

### B. Prebuilt headless binary (up to date)

[ROllerozxa/luantiserver](https://github.com/rollerozxa/luantiserver) publishes
CI-built `luantiserver-x.y.z-x86_64.tar.gz` for each release (this is what the
official [Luanti docs](https://docs.luanti.org/for-server-hosts/setup/linux/)
recommend). Unpack it somewhere; it contains `bin/luantiserver` plus the
engine's `builtin/` scripts.

### C. Build from source (fully offline / air-gapped)

If your host can reach GitHub but has no packages (e.g. a locked-down
container), build a headless server with only C toolchain + `cmake`:

```bash
# deps, built from source into $PREFIX (see notes below)
#   zlib, zstd, sqlite3 (amalgamation), LuaJIT
# GMP and jsoncpp are NOT needed: Luanti falls back to its bundled
# mini-gmp and jsoncpp automatically (-DENABLE_SYSTEM_GMP=0 -DENABLE_SYSTEM_JSONCPP=0)

cmake -S luanti-5.17.0 -B build \
  -DBUILD_CLIENT=0 -DBUILD_SERVER=1 -DRUN_IN_PLACE=1 \
  -DENABLE_CURL=0 -DENABLE_GETTEXT=0 -DENABLE_SOUND=0 -DENABLE_CURSES=0 \
  -DENABLE_POSTGRESQL=0 -DENABLE_LEVELDB=0 -DENABLE_REDIS=0 \
  -DENABLE_SPATIAL=0 -DENABLE_OPENSSL=0 \
  -DZLIB_LIBRARY=$PREFIX/lib/libz.a -DZLIB_INCLUDE_DIR=$PREFIX/include \
  -DZSTD_LIBRARY=$PREFIX/lib/libzstd.a -DZSTD_INCLUDE_DIR=$PREFIX/include \
  -DSQLITE3_LIBRARY=$PREFIX/lib/libsqlite3.a -DSQLITE3_INCLUDE_DIR=$PREFIX/include \
  -DLUA_LIBRARY=$PREFIX/lib/libluajit-5.1.a -DLUA_INCLUDE_DIR=$PREFIX/include/luajit-2.1
cmake --build build -j$(nproc)
# result: build/bin/luantiserver
```

`ENABLE_CURL=0` is the only real trade-off: without cURL the server cannot
announce itself to the public server list (see §7). Everything else (joinable
address, web clients, match play) works fine.

## 2. Install the game

Luanti finds games through its *subgame path*. Create a `games/` directory next
to the server binary and put the repo there (copy, or symlink for dev):

```bash
mkdir -p /srv/systemloot/games
ln -s /path/to/SystemTest /srv/systemloot/games/SystemTest   # game id = folder name
```

Or, without touching the server layout, point the engine at it:

```bash
export MINETEST_SUBGAME_PATH=/path/to/SystemTest
```

## 3. Server layout & first boot

A clean layout keeps the world, config and logs in one place:

```
/srv/systemloot/
├── bin/luantiserver            # engine
├── builtin/                    # engine scripts (from the engine package)
├── games/SystemTest -> …       # this repo
├── worlds/systemloot/          # world files (created on first boot)
├── systemloot.conf             # server config
└── run_server.sh
```

`run_server.sh` — restarts the server if it crashes (see
[Luanti docs](https://docs.luanti.org/for-server-hosts/setup/linux/)):

```bash
#!/bin/bash
cd "$(dirname "$0")"
while true; do
  ./bin/luantiserver --gameid SystemTest --world worlds/systemloot \
                     --config systemloot.conf --logfile server.log --terminal
  sleep 2
done
```

First boot creates the world. The game **auto-builds its deterministic arena**
(beacons, monster-master base, cloud cage) at `(0,0,0)` on world generation —
no manual map work needed. You should see in `server.log`:

```
Server for gameid "SystemTest" listening on port 30000
[game_mode] Loaded core PvP game mode with beacons and monster master
[sl_test] deterministic arena generated at (0,0,0)
```

## 4. `systemloot.conf` — public server config

```ini
# --- identity (shown in the server list / client) ---
server_name = System Looting — Official Test Server
server_description = Competitive team survival: craft, scavenge, defend the beacons.
motd = Welcome! Lobby open — matches start automatically when enough players join.
server_announce = false        # set true if engine built with cURL (§7)

# --- network ---
port = 30000
bind_address = 0.0.0.0
max_users = 12

# --- gameplay (System Looting) ---
mg_name = singlenode           # arena is hand-built; no terrain generation
time_speed = 0                 # matches run on the game's own clock (game.conf)

# The game's own settings (see settingtypes.txt):
sl_auto_start = true           # auto-start matches when lobby is full enough
sl_auto_start_delay = 15

# --- safety (public server hygiene, per Luanti docs) ---
enable_damage = true
default_password = <set-one>
# never disable mod security:
# secure.enable_security = true
```

> **`mg_name = singlenode` is critical.** The world must not regenerate terrain
> over the arena. Set it in the config *and* in `worlds/systemloot/world.mt`
> (`mg_name=singlenode`, `gameid=SystemTest`, `backend=sqlite3`).

### World bootstrap by hand (optional)

You can pre-create the world instead of letting the server do it:

```bash
mkdir -p worlds/systemloot
printf 'gameid = SystemTest\nbackend = sqlite3\nmg_name = singlenode\n' > worlds/systemloot/world.mt
```

## 5. systemd unit (recommended for a VPS)

`/etc/systemd/system/systemloot.service`:

```ini
[Unit]
Description=System Looting Luanti server
After=network.target

[Service]
User=systemloot
Group=systemloot
WorkingDirectory=/srv/systemloot
ExecStart=/srv/systemloot/bin/luantiserver --gameid SystemTest --world worlds/systemloot --config systemloot.conf --logfile server.log
Restart=on-failure
RestartSec=3
# hardening
NoNewPrivileges=true
PrivateTmp=true

[Install]
WantedBy=multi-user.target
```

```bash
sudo useradd -r -m -d /srv/systemloot systemloot
sudo systemctl daemon-reload && sudo systemctl enable --now systemloot
journalctl -u systemloot -f
```

## 6. Docker (alternative)

The [linuxserver/luanti](https://github.com/linuxserver/docker-luanti) image is
the most common container option:

```yaml
services:
  luanti:
    image: lscr.io/linuxserver/luanti:latest
    environment:
      - PUID=1000
      - PGID=1000
      - TZ=UTC
      - "CLI_ARGS=--gameid SystemTest"
    volumes:
      - ./data:/config/.minetest
      - ./SystemTest:/config/.minetest/games/SystemTest:ro   # this repo
    ports:
      - "30000:30000/udp"
      - "30000:30000/tcp"
    restart: unless-stopped
```

## 7. Make it public

1. **Firewall** — open port `30000` TCP *and* UDP:
   ```bash
   sudo ufw allow 30000/tcp && sudo ufw allow 30000/udp
   ```
2. **Port forwarding** — on a home router, forward TCP+UDP `30000` to the
   server's LAN IP. A VPS needs no forwarding (see the Luanti
   [port-forwarding guide](https://docs.luanti.org/for-server-hosts/setup/)).
3. **Server list** — to appear in the in-game server list, the engine must be
   built with cURL and you set `server_announce = true`, `server_name`, and a
   public `server_address` (domain only). Without cURL the server is still
   joinable directly by address; it just won't be listed.
4. **Web clients** — the WASM build (GitHub Pages / itch) connects through the
   dustlabs WebSocket proxies (`wss://luanti.dustlabs.io/proxy` and regional
   ones, selectable in the launcher). Players enter your server address in the
   *Join Server* dialog; the proxy bridges to your TCP port. For full control
   you can host your own proxy:
   [paradust7/webshims](https://github.com/paradust7/webshims) (its
   `proxy.js`), then point the client at it.

## 8. Admin operations

Give yourself admin on first join (or use `--world` + auth file):

```bash
# console (server stdin) while running:
#   (no chat from console; use the client instead)
```

In-game, with the `sl_admin` privilege (grant via `/grant <name> sl_admin` as a
server admin, or `singleplayer`/`server` admin priv):

| Command | Effect |
|---|---|
| `/sl_match_start` / `/sl_match_start now` | ready check / instant start |
| `/sl_match_stop` | force-stop current match |
| `/sl_autostart on\|off\|status` | toggle lobby auto-start |
| `/sl_assign <name> <team>` | assign a player to a team |
| `/sl_set_lobby` | set lobby spawn to your position |
| `/sl_test_arena` (creative) | (re)build the test arena |
| `/sl_state` | inspect your team/role/phase |

Player commands: `/sl_ready` (confirm ready check), `/sl_be_monster_master`
(first come, first served), `/sl_mm_return`, `/sl_summon_ghost`,
`/sl_ghost_offer`.

## 9. Verification checklist

```bash
# 1) process up and listening
ss -lunp | grep 30000 && ss -ltnp | grep 30000
# 2) boot log proves game loaded
grep -E "Loaded core PvP game mode|listening on port|arena generated" server.log
# 3) from another machine: the server list ping is UDP; the join is TCP
nc -vz <server-ip> 30000
```

Smoke/soak tests exist in-repo (`tests/smoke_test.lua` and
`tests/soak/run_soak.py`) and run against a live engine — use them as a
pre-flight before opening the port to the public.

## 10. Troubleshooting

- **`Multiple worlds are available`** — pass `--worldname` or `--world`.
- **Terrain appears over the arena** — `mg_name` was not `singlenode`; fix
  config + `world.mt`, and rebuild the arena with `/sl_test_arena`.
- **Game not found** — wrong `games/` path or `MINETEST_SUBGAME_PATH`; the
  folder name is the game id (`SystemTest`).
- **No server list entry** — engine built without cURL, or `server_announce`
  off; join by address instead.
- **Web client can't connect** — pick a closer dustlabs region proxy, or check
  the server's TCP port is reachable from the internet (not just LAN).
