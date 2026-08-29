#!/bin/bash
# host_public.sh — run a PUBLIC System Looting server from your own machine.
#
# Why this exists: free sandboxes/CI cannot host a public Luanti server
# (no public UDP port; outbound TLS to tunnel providers is filtered).
# On YOUR machine this works: it installs the engine + game, starts the
# server, and hands you a playit.gg claim link. After claiming, you get a
# public address like 123.45.67.89:51234 that anyone can join.
#
# Requirements: Linux x86_64 with internet access (Ubuntu/Debian
# recommended), or run each step manually on Windows (see docs/PUBLIC_DEPLOY.md).
#
# Usage:  bash host_public.sh
set -euo pipefail

HOST_DIR="${SYSTEMLOOT_DIR:-$HOME/systemloot}"
GAME_REPO="https://github.com/SodoMita/SystemTest.git"
PORT=30000

echo "== System Looting public host =="
echo "Install dir: $HOST_DIR"
mkdir -p "$HOST_DIR"
cd "$HOST_DIR"

# --- 1. Engine -----------------------------------------------------------
ENGINE=""
if command -v luantiserver >/dev/null 2>&1; then
  ENGINE=$(command -v luantiserver)
elif command -v minetestserver >/dev/null 2>&1; then
  ENGINE=$(command -v minetestserver)
else
  echo ">> Installing engine via apt (luanti-server)…"
  sudo apt-get update -qq && sudo apt-get install -y luanti-server || \
    sudo apt-get install -y minetest-server
  ENGINE=$(command -v luantiserver || command -v minetestserver)
fi
[ -n "$ENGINE" ] || { echo "ERROR: no luantiserver binary. Install luanti-server or minetest-server."; exit 1; }
echo ">> Engine: $ENGINE ($("$ENGINE" --version | head -1))"

# --- 2. Game -------------------------------------------------------------
if [ ! -d "$HOST_DIR/games/SystemTest" ]; then
  echo ">> Cloning System Looting…"
  git clone -q --depth 1 "$GAME_REPO" "$HOST_DIR/games/SystemTest"
fi

# --- 3. World + config ---------------------------------------------------
mkdir -p "$HOST_DIR/worlds/systemloot"
printf 'gameid = SystemTest\nbackend = sqlite3\nmg_name = singlenode\n' > "$HOST_DIR/worlds/systemloot/world.mt"
cat > "$HOST_DIR/systemloot.conf" <<EOF
server_name = System Looting — Public
server_description = Competitive team survival. Join!
motd = Welcome! Lobby open — matches auto-start.
port = $PORT
bind_address = 0.0.0.0
max_users = 16
mg_name = singlenode
time_speed = 0
enable_damage = true
sl_auto_start = true
sl_auto_start_delay = 20
EOF

# --- 4. Start the server ------------------------------------------------
echo ">> Starting Luanti server on port $PORT (gameid SystemTest)…"
nohup "$ENGINE" --server --gameid SystemTest \
  --world "$HOST_DIR/worlds/systemloot" \
  --config "$HOST_DIR/systemloot.conf" \
  --logfile "$HOST_DIR/server.log" >/dev/null 2>&1 &
sleep 4
if ! (ss -lun 2>/dev/null | grep -q ":$PORT") && ! (netstat -lun 2>/dev/null | grep -q ":$PORT"); then
  echo "WARNING: server may not be listening yet — check $HOST_DIR/server.log"
else
  echo ">> Server listening on UDP :$PORT (log: $HOST_DIR/server.log)"
fi
grep -q "Loaded core PvP game mode" "$HOST_DIR/server.log" && echo ">> Game loaded OK ✔" || echo ">> (waiting for game load — see log)"

# --- 5. playit.gg tunnel ------------------------------------------------
if [ ! -x "$HOST_DIR/playit" ]; then
  echo ">> Downloading playit agent…"
  curl -SsL "https://playit.gg/download/playit-linux-amd64" -o "$HOST_DIR/playit"
  chmod +x "$HOST_DIR/playit"
fi

echo ""
echo "==================================================================="
echo "  NEXT STEPS (once):"
echo "  1. Run:  $HOST_DIR/playit"
echo "  2. Open the CLAIM LINK it prints (https://playit.gg/claim/...)"
echo "     and create the free playit account — the agent binds to you."
echo "  3. In the playit dashboard add a tunnel:"
echo "       Protocol: UDP | Local port: $PORT  (add TCP $PORT too)"
echo "  4. playit shows a public address like 123.45.67.89:51234."
echo "     Share THAT address — anyone joins it from Luanti."
echo "==================================================================="
echo ""
echo "Keep this terminal open (or run playit under systemd/tmux)."
echo "Docs: docs/PUBLIC_DEPLOY.md in the repo."
