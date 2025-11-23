#!/bin/bash
# MTProxy Ultimate One-Click Installer (FakeTLS + 8443 + mtproxy user)
set -euo pipefail

PORT=8443
UDP_PORT=8888
WORKDIR="/etc/mtproto-proxy"
BIN_PATH="/usr/local/bin/mtproto-proxy"

GREEN='\033[0;32m'; NC='\033[0m'
log(){ echo -e "${GREEN}[INFO]${NC} $*"; }

log "Installing system dependencies..."
if [[ -f /etc/debian_version ]]; then
    apt update
    apt install -y build-essential libssl-dev zlib1g-dev git curl
elif [[ -f /etc/redhat-release ]]; then
    yum install -y gcc make openssl-devel zlib-devel git curl
else
    echo "Unsupported OS"; exit 1
fi

log "Creating mtproxy user..."
id -u mtproxy &>/dev/null || useradd -r -s /sbin/nologin mtproxy

log "Cloning MTProxy..."
cd /tmp
rm -rf MTProxy
git clone --depth 1 https://github.com/TelegramMessenger/MTProxy
cd MTProxy

log "Compiling MTProxy..."
make clean
make -j$(nproc)
cp objs/bin/mtproto-proxy "$BIN_PATH"
chmod +x "$BIN_PATH"

log "Preparing configuration..."
mkdir -p "$WORKDIR"
cd "$WORKDIR"

log "Downloading proxy-secret and proxy-multi.conf..."
curl -s -O https://core.telegram.org/getProxySecret
curl -s -O https://core.telegram.org/getProxyConfig

# Ensure mtproxy can read files
chown -R mtproxy:mtproxy "$WORKDIR"
chmod 644 proxy-secret proxy-multi.conf

# Generate FakeTLS Secret
SECRET=$(openssl rand -hex 16)
log "Generated FakeTLS Secret: $SECRET"

# Create systemd service
log "Creating systemd service..."
cat > /etc/systemd/system/mtproto-proxy.service <<EOF
[Unit]
Description=MTProto Proxy (FakeTLS)
After=network.target

[Service]
Type=simple
User=mtproxy
WorkingDirectory=$WORKDIR
ExecStart=$BIN_PATH -p $UDP_PORT -H $PORT -S $SECRET --aes-pwd $WORKDIR/proxy-secret $WORKDIR/proxy-multi.conf -M 1
Restart=always
RestartSec=5
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF

log "Opening firewall port $PORT..."
if command -v ufw >/dev/null 2>&1; then
    ufw allow $PORT/tcp
    ufw reload
elif command -v firewall-cmd >/dev/null 2>&1; then
    firewall-cmd --add-port=$PORT/tcp --permanent
    firewall-cmd --reload
else
    iptables -I INPUT -p tcp --dport $PORT -j ACCEPT || true
fi

log "Starting MTProxy service..."
systemctl daemon-reload
systemctl enable --now mtproto-proxy

sleep 2
if systemctl is-active --quiet mtproto-proxy; then
    log "MTProxy is running successfully!"
else
    echo "MTProxy failed to start. Check logs:"
    journalctl -u mtproto-proxy -n 50 --no-pager
    exit 1
fi

IP=$(curl -s -4 ip.sb || echo "SERVER_IP")
echo
log "=== MTProxy Installation Complete ==="
echo "IP: $IP"
echo "Port (FakeTLS): $PORT"
echo "UDP Port: $UDP_PORT"
echo "Secret: $SECRET"
echo "Telegram link: tg://proxy?server=$IP&port=$PORT&secret=$SECRET"
