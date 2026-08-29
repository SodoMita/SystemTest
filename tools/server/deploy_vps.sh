#!/bin/bash
# deploy_vps.sh — one-shot deploy of a public System Looting server on a fresh
# Debian/Ubuntu VPS (works on Oracle Always Free ARM, GCP e2-micro, any VPS).
# Run as root (or with sudo) ON the VPS:
#   curl -sSL https://raw.githubusercontent.com/SodoMita/SystemTest/arena/01a04bf2-systemtest/tools/server/deploy_vps.sh -o deploy_vps.sh
#   bash deploy_vps.sh
set -euo pipefail

HOST_DIR=/srv/systemloot
PORT=30000

echo "== System Looting VPS deploy =="
[ "$(id -u)" = 0 ] || { echo "run as root: sudo bash deploy_vps.sh"; exit 1; }

# 1. engine
apt-get update -qq
apt-get install -y -qq luanti-server || apt-get install -y -qq minetest-server
ENGINE=$(command -v luantiserver || command -v minetestserver)
echo ">> engine: $ENGINE ($("$ENGINE" --version | head -1))"

# 2. game
mkdir -p "$HOST_DIR/games"
[ -d "$HOST_DIR/games/SystemTest" ] || git clone -q --depth 1 \
  https://github.com/SodoMita/SystemTest "$HOST_DIR/games/SystemTest"

# 3. world + config
mkdir -p "$HOST_DIR/worlds/systemloot"
printf 'gameid = SystemTest\nbackend = sqlite3\nmg_name = singlenode\n' > "$HOST_DIR/worlds/systemloot/world.mt"
cat > "$HOST_DIR/systemloot.conf" <<CONF
server_name = System Looting — Public
server_description = Competitive team survival. Join!
server_announce = true
motd = Welcome! Lobby open — matches auto-start.
port = $PORT
bind_address = 0.0.0.0
max_users = 16
mg_name = singlenode
time_speed = 0
enable_damage = true
sl_auto_start = true
sl_auto_start_delay = 20
CONF

# 4. systemd service
id systemloot >/dev/null 2>&1 || useradd -r -m -d "$HOST_DIR" systemloot
chown -R systemloot:systemloot "$HOST_DIR"
cat > /etc/systemd/system/systemloot.service <<SVC
[Unit]
Description=System Looting Luanti server
After=network.target

[Service]
User=systemloot
WorkingDirectory=$HOST_DIR
ExecStart=$ENGINE --gameid SystemTest --world $HOST_DIR/worlds/systemloot --config $HOST_DIR/systemloot.conf --logfile $HOST_DIR/server.log
Restart=on-failure
RestartSec=3
NoNewPrivileges=true

[Install]
WantedBy=multi-user.target
SVC
systemctl daemon-reload
systemctl enable --now systemloot
sleep 4

# 5. firewall
if command -v ufw >/dev/null 2>&1; then
  ufw allow ${PORT}/tcp >/dev/null && ufw allow ${PORT}/udp >/dev/null && ufw --force enable >/dev/null || true
fi

# 6. verify
IP=$(curl -4 -s --max-time 10 https://ipv4.icanhazip.com || hostname -I | awk '{print $1}')
echo ""
echo "==================================================================="
echo "  DONE — server: $(systemctl is-active systemloot)"
echo "  Log: journalctl -u systemloot -f"
echo "  Public address for players:  $IP:$PORT"
echo "  (server_announce = true → appears in Luanti's server list too)"
echo "==================================================================="
