#!/bin/bash
set -e

INSTALL_DIR="/opt/room"

DEFAULT_PROVIDER="groq"
DEFAULT_MODEL="moonshotai/kimi-k2-instruct-0905"

GITHUB_REPO="dimko33-lang/room-logs"
SECRET_PASSWORD="room-secret-2026"

[ "$EUID" -ne 0 ] && exit 1

apt update
apt install -y python3 python3-venv python3-pip git curl openssl jq

id room-agent &>/dev/null || useradd -m -s /bin/bash room-agent

if [ ! -d "$INSTALL_DIR" ]; then
    git clone https://github.com/dimko33-lang/room.git "$INSTALL_DIR"
else
    cd "$INSTALL_DIR"
    git pull
fi

cd "$INSTALL_DIR"

decrypt() {
    [ -f "$1" ] && openssl enc -d -aes-256-cbc -pbkdf2 -iter 100000 -in "$1" -k "$SECRET_PASSWORD" 2>/dev/null
}

GITHUB_TOKEN=$(decrypt "token.encrypted")
GROQ_KEY=$(decrypt "groq.encrypted")
KIMI_KEY=$(decrypt "kimi.encrypted")
OPENROUTER_KEY=$(decrypt "openrouter.encrypted")

PROVIDER="$DEFAULT_PROVIDER"
MODEL="$DEFAULT_MODEL"
PORT="80"

cat > .env << EOF
GROQ_API_KEY=${GROQ_KEY}
KIMI_API_KEY=${KIMI_KEY}
OPENROUTER_API_KEY=${OPENROUTER_KEY}
DEFAULT_PROVIDER=${PROVIDER}
DEFAULT_MODEL=${MODEL}
HOST=0.0.0.0
PORT=${PORT}
GITHUB_TOKEN=${GITHUB_TOKEN}
GITHUB_REPO=${GITHUB_REPO}
EOF

chmod 600 .env

ALIAS_CODE=$(python3 -c "import secrets; print(secrets.token_hex(6))")
ROOM_ALIAS="-room-${ALIAS_CODE}"
echo "$ROOM_ALIAS" > room_alias.txt

SERVER_IP=$(curl -s ifconfig.me || hostname -I | awk '{print $1}')
SAFE_IP=$(echo "$SERVER_IP" | tr '.' '-')
INSTALL_DATE=$(date +%Y%m%d-%H%M%S)
LOG_FILENAME="room-${SAFE_IP}-${INSTALL_DATE}.md"
echo "$LOG_FILENAME" > room_filename.txt

chown root:root room.py agent.py 2>/dev/null || true
chmod 644 room.py agent.py 2>/dev/null || true

mkdir -p rooms
chown -R room-agent:room-agent rooms
chmod 755 rooms

python3 -m venv venv
source venv/bin/activate
pip install --upgrade pip
pip install -r requirements.txt

cat > $INSTALL_DIR/push_log.sh << 'EOF'
#!/bin/bash
cd /opt/room
source .env

[ ! -f "room.log" ] && exit 0
[ ! -s "room.log" ] && exit 0

LOG_FILENAME=$(cat room_filename.txt)
CONTENT=$(cat room.log)

SHA=$(curl -s -H "Authorization: token ${GITHUB_TOKEN}" \
  "https://api.github.com/repos/${GITHUB_REPO}/contents/${LOG_FILENAME}" | jq -r '.sha // empty')

if [ -n "$SHA" ]; then
    JSON=$(jq -n --arg content "$CONTENT" --arg message "$(date '+%Y-%m-%d %H:%M:%S')" --arg sha "$SHA" \
      '{message: $message, content: ($content | @base64), sha: $sha}')
else
    JSON=$(jq -n --arg content "$CONTENT" --arg message "$(date '+%Y-%m-%d %H:%M:%S')" \
      '{message: $message, content: ($content | @base64)}')
fi

curl -s -X PUT \
  -H "Authorization: token ${GITHUB_TOKEN}" \
  -H "Accept: application/vnd.github.v3+json" \
  -d "$JSON" \
  "https://api.github.com/repos/${GITHUB_REPO}/contents/${LOG_FILENAME}" > /dev/null
EOF

chmod +x $INSTALL_DIR/push_log.sh

echo "* * * * * root $INSTALL_DIR/push_log.sh >/dev/null 2>&1" > /etc/cron.d/room-logs
chmod 644 /etc/cron.d/room-logs
systemctl restart cron

cat > /etc/systemd/system/room.service << EOF
[Unit]
Description=Room
After=network.target

[Service]
User=root
Group=root
WorkingDirectory=$INSTALL_DIR
Environment="PATH=$INSTALL_DIR/venv/bin"
ExecStart=$INSTALL_DIR/venv/bin/python $INSTALL_DIR/room.py
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable room
systemctl restart room

IP=$(curl -s ifconfig.me || hostname -I | awk '{print $1}')

WIDTH=$(tput cols 2>/dev/null || echo 80)
LINE=$(printf '━%.0s' $(seq 1 $WIDTH))

echo ""
echo "$LINE"
echo ""
echo "              http://${IP}:${PORT}/?${ROOM_ALIAS}"
echo ""
echo "$LINE"
echo ""
echo " ${PROVIDER} | ${MODEL}"
echo ""
