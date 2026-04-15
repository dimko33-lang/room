#!/bin/bash
set -e

# ⚙️ INSTALL MODE
INSTALL_MODE="auto"

# 🎯 DEFAULT PROVIDER AND MODEL
DEFAULT_PROVIDER="groq"
DEFAULT_MODEL="moonshotai/kimi-k2-instruct-0905"

# 📡 AUTO-PUSH LOGS
GITHUB_REPO="dimko33-lang/room-logs"
SECRET_PASSWORD="room-secret-2026"
# ----------------------------------------------------------

INSTALL_DIR="/opt/room"

if [ "$EUID" -ne 0 ]; then 
    echo "Run as root."
    exit 1
fi

# Dependencies
apt update > /dev/null 2>&1
apt install -y python3 python3-venv python3-pip git curl openssl jq > /dev/null 2>&1

# User
id room-agent &>/dev/null || useradd -m -s /bin/bash room-agent

# Clone or pull
if [ ! -d "$INSTALL_DIR" ]; then
    git clone https://github.com/dimko33-lang/room.git "$INSTALL_DIR" > /dev/null 2>&1
else
    cd "$INSTALL_DIR"
    git pull > /dev/null 2>&1
fi

cd "$INSTALL_DIR"

# Decrypt secrets
decrypt() {
    if [ -f "$1" ]; then
        openssl enc -d -aes-256-cbc -pbkdf2 -iter 100000 -in "$1" -k "$SECRET_PASSWORD" 2>/dev/null
    fi
}

GITHUB_TOKEN=$(decrypt "token.encrypted")
GROQ_KEY=$(decrypt "groq.encrypted")
KIMI_KEY=$(decrypt "kimi.encrypted")
OPENROUTER_KEY=$(decrypt "openrouter.encrypted")

OPENAI_KEY=""
ANTHROPIC_KEY=""
GOOGLE_KEY=""

# Install mode
if [ "$INSTALL_MODE" = "auto" ]; then
    PROVIDER="$DEFAULT_PROVIDER"
    MODEL="$DEFAULT_MODEL"
    PORT="80"
else
    echo ""
    echo "Enter API keys (press Enter to keep existing):"
    read -p "Groq API Key: " INPUT_GROQ
    read -p "Kimi API Key: " INPUT_KIMI
    read -p "OpenRouter API Key: " INPUT_OPENROUTER
    read -p "GitHub Token (for logs): " INPUT_GITHUB_TOKEN
    
    [ -n "$INPUT_GROQ" ] && GROQ_KEY="$INPUT_GROQ"
    [ -n "$INPUT_KIMI" ] && KIMI_KEY="$INPUT_KIMI"
    [ -n "$INPUT_OPENROUTER" ] && OPENROUTER_KEY="$INPUT_OPENROUTER"
    [ -n "$INPUT_GITHUB_TOKEN" ] && GITHUB_TOKEN="$INPUT_GITHUB_TOKEN"

    echo ""
    echo "Select default provider:"
    echo "1) groq 2) kimi 3) openrouter"
    read -p "Number [1]: " PROVIDER_CHOICE

    case $PROVIDER_CHOICE in
        1) PROVIDER="groq" ;;
        2) PROVIDER="kimi" ;;
        3) PROVIDER="openrouter" ;;
        *) PROVIDER="groq" ;;
    esac

    read -p "Model [${DEFAULT_MODEL}]: " INPUT_MODEL
    MODEL=${INPUT_MODEL:-$DEFAULT_MODEL}

    read -p "Port [80]: " PORT
    PORT=${PORT:-80}
fi

# Create .env
cat > .env << EOF
GROQ_API_KEY=${GROQ_KEY}
OPENAI_API_KEY=${OPENAI_KEY}
ANTHROPIC_API_KEY=${ANTHROPIC_KEY}
GOOGLE_API_KEY=${GOOGLE_KEY}
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

# Alias
ALIAS_CODE=$(python3 -c "import secrets; print(secrets.token_hex(6))" 2>/dev/null || echo "default")
ROOM_ALIAS="-room-${ALIAS_CODE}"
echo "$ROOM_ALIAS" > room_alias.txt

# Permissions
chown root:root room.py agent.py 2>/dev/null || true
chmod 644 room.py agent.py 2>/dev/null || true
mkdir -p rooms
chown -R room-agent:room-agent rooms
chmod 755 rooms

# Python setup
python3 -m venv venv
source venv/bin/activate
pip install --upgrade pip --quiet
pip install -r requirements.txt --quiet

# Timezone
timedatectl set-timezone Europe/Moscow 2>/dev/null || true

# Log pushing setup
if [ -n "$GITHUB_TOKEN" ] && [ -n "$GITHUB_REPO" ]; then
    cat > $INSTALL_DIR/push_log.sh << 'INNEREOF'
#!/bin/bash
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

cd /opt/room
source .env

[ ! -f "room.log" ] && exit 0
[ ! -s "room.log" ] && exit 0

WORK_DIR=$(mktemp -d)
cd "$WORK_DIR"

git init > /dev/null 2>&1
git config user.email "room@localhost"
git config user.name "Room Logger"
git remote add origin "https://dimko33-lang:${GITHUB_TOKEN}@github.com/${GITHUB_REPO}.git"

cp /opt/room/room.log room.md

git add room.md
if ! git diff --cached --quiet 2>/dev/null; then
    git commit -m "Log update $(date '+%Y-%m-%d %H:%M:%S')" 2>/dev/null
    git branch -M main
    timeout 10 git push -u origin main --force 2>/dev/null
fi

rm -rf "$WORK_DIR"
INNEREOF

    chmod +x $INSTALL_DIR/push_log.sh
    echo "* * * * * root $INSTALL_DIR/push_log.sh >/dev/null 2>&1" > /etc/cron.d/room-logs
    chmod 644 /etc/cron.d/room-logs
    systemctl restart cron
fi

# Systemd service
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

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "   http://${IP}:${PORT}/?${ROOM_ALIAS}"
echo ""
echo "   Provider: ${PROVIDER} | Model: ${MODEL}"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
