#!/bin/bash
# Patches the web client to use THIS container's own WebSocket proxy (same
# origin), enables auto-join, then starts: Luanti server (UDP 30000) + client/proxy (PORT).
set -e
GAME=/app/game
PAGES=/app/pages
LUA="$(command -v luantiserver || command -v minetestserver)"
PORT="${PORT:-8080}"

# --- world + config ---
mkdir -p "$GAME/worlds/systemloot"
printf 'gameid = SystemTest\nbackend = sqlite3\nmg_name = singlenode\n' > "$GAME/worlds/systemloot/world.mt"
cat > "$GAME/systemloot.conf" <<CONF
server_name = System Looting — Public
server_description = Competitive team survival.
port = 30000
bind_address = 0.0.0.0
max_users = 16
mg_name = singlenode
time_speed = 0
enable_damage = true
sl_auto_start = true
sl_auto_start_delay = 20
CONF

# --- patch the client: same-origin proxy + auto-join ---
LJS=$(find "$PAGES" -name launcher.js | head -1)
python3 - "$LJS" "$PAGES/index.html" <<'PYEOF'
import sys
ljs, idx = sys.argv[1], sys.argv[2]
s = open(ljs).read()
s = s.replace('this.proxyUrl = "wss://luanti.dustlabs.io/proxy";',
              'this.proxyUrl = (location.protocol === "https:" ? "wss://" : "ws://") + location.host;')
open(ljs, 'w').write(s)
i = open(idx).read()
old = '''const proxies = [
              [ "wss://na1.dustlabs.io/mtproxy", "North America" ],'''
new = '''const proxies = [
              [ (location.protocol === "https:" ? "wss://" : "ws://") + location.host, "This server" ],
              [ "wss://na1.dustlabs.io/mtproxy", "North America" ],'''
assert old in i
open(idx, 'w').write(i.replace(old, new))
PYEOF

# --- start Luanti server ---
nohup "$LUA" --server --gameid SystemTest \
  --world "$GAME/worlds/systemloot" --config "$GAME/systemloot.conf" \
  --logfile "$GAME/server.log" >/dev/null 2>&1 &

# --- start client+proxy ---
cd /app/tools
PORT="$PORT" WWW_ROOT="$PAGES" node allinone.js
