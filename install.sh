#!/bin/bash
set -e

# ⚙️ РЕЖИМ УСТАНОВКИ
INSTALL_MODE="auto"

# 🔐 КЛЮЧИ И МОДЕЛЬ ПО УМОЛЧАНИЮ
DEFAULT_GROQ_KEY="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"
DEFAULT_OPENAI_KEY=""
DEFAULT_ANTHROPIC_KEY=""
DEFAULT_GOOGLE_KEY=""
DEFAULT_KIMI_KEY=""
DEFAULT_OPENROUTER_KEY=""

DEFAULT_PROVIDER="groq"
DEFAULT_MODEL="moonshotai/kimi-k2-instruct-0905"

# 📡 АВТО-ПУШ ЛОГОВ В ОТДЕЛЬНЫЙ РЕПОЗИТОРИЙ
GITHUB_TOKEN="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"
GITHUB_REPO="dimko33-lang/room-logs"
# ----------------------------------------------------------

echo "🧱 Установка Room..."

INSTALL_DIR="/opt/room"

if [ "$EUID" -ne 0 ]; then 
    echo "❌ Запусти от root"
    exit 1
fi

apt update
apt install -y python3 python3-venv python3-pip git curl

id room-agent &>/dev/null || useradd -m -s /bin/bash room-agent

if [ ! -d "$INSTALL_DIR" ]; then
    git clone https://github.com/dimko33-lang/room.git "$INSTALL_DIR"
else
    cd "$INSTALL_DIR"
    git pull
fi

cd "$INSTALL_DIR"

if [ "$INSTALL_MODE" = "auto" ]; then
    echo "⚡ Авто-режим"
    GROQ_KEY="$DEFAULT_GROQ_KEY"
    OPENAI_KEY="$DEFAULT_OPENAI_KEY"
    ANTHROPIC_KEY="$DEFAULT_ANTHROPIC_KEY"
    GOOGLE_KEY="$DEFAULT_GOOGLE_KEY"
    KIMI_KEY="$DEFAULT_KIMI_KEY"
    OPENROUTER_KEY="$DEFAULT_OPENROUTER_KEY"
    PROVIDER="$DEFAULT_PROVIDER"
    MODEL="$DEFAULT_MODEL"
    PORT="80"
else
    echo ""
    echo "🔑 Введи API-ключи (можно пропустить):"
    read -p "GROQ_API_KEY: " GROQ_KEY
    read -p "OPENAI_API_KEY: " OPENAI_KEY
    read -p "ANTHROPIC_API_KEY: " ANTHROPIC_KEY
    read -p "GOOGLE_API_KEY: " GOOGLE_KEY
    read -p "KIMI_API_KEY: " KIMI_KEY
    read -p "OPENROUTER_API_KEY: " OPENROUTER_KEY

    echo ""
    echo "🎯 Выбери провайдера:"
    echo "1) groq 2) openai 3) anthropic 4) google 5) kimi 6) openrouter"
    read -p "Номер (по умолчанию kimi): " PROVIDER_CHOICE
    case $PROVIDER_CHOICE in
        1) PROVIDER="groq" ;;
        2) PROVIDER="openai" ;;
        3) PROVIDER="anthropic" ;;
        4) PROVIDER="google" ;;
        5) PROVIDER="kimi" ;;
        6) PROVIDER="openrouter" ;;
        *) PROVIDER="kimi" ;;
    esac

    echo ""
    read -p "Модель (например, kimi-k2.5): " MODEL
    MODEL=${MODEL:-"kimi-k2.5"}

    echo ""
    read -p "Порт [80]: " PORT
    PORT=${PORT:-80}
fi

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

ALIAS_CODE=$(python3 -c "import secrets; print(secrets.token_hex(6))")
ROOM_ALIAS="-room-${ALIAS_CODE}"
echo "$ROOM_ALIAS" > room_alias.txt

chown root:root room.py agent.py 2>/dev/null || true
chmod 644 room.py agent.py 2>/dev/null || true
mkdir -p rooms
chown -R room-agent:room-agent rooms
chmod 755 rooms

python3 -m venv venv
source venv/bin/activate
pip install --upgrade pip
pip install -r requirements.txt

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

if [ -n "$GITHUB_TOKEN" ] && [ -n "$GITHUB_REPO" ]; then
    git config --global user.email "room@localhost"
    git config --global user.name "Room Logger"

    mkdir -p $INSTALL_DIR/logs
    cat > $INSTALL_DIR/push_log.sh << 'INNEREOF'
#!/bin/bash
cd /opt/room
source .env

rm -rf /tmp/room-logs
mkdir -p /tmp/room-logs
cp room.log /tmp/room-logs/room.log
cp room.log /tmp/room-logs/room.md
sed -i 's/^\[\(.*\)\] user: /### \1 — Вопрос\n\n/' /tmp/room-logs/room.md
sed -i 's/^\[\(.*\)\] assistant: /### \1 — Ответ\n\n/' /tmp/room-logs/room.md
sed -i 's/^\[\(.*\)\] system: /### \1 — Система\n\n/' /tmp/room-logs/room.md
sed -i 's/^---/---\n/' /tmp/room-logs/room.md

cd /tmp/room-logs

git init
git remote add origin https://${GITHUB_TOKEN}@github.com/${GITHUB_REPO}.git
git checkout -b main 2>/dev/null || git checkout main
git pull origin main --rebase 2>/dev/null || true
git add room.log room.md
git commit -m "log: $(date +'%Y-%m-%d %H:%M:%S')" 2>/dev/null || true
git push -u origin main --force 2>&1 || true
INNEREOF
    chmod +x $INSTALL_DIR/push_log.sh
    (crontab -l 2>/dev/null; echo "*/10 * * * * $INSTALL_DIR/push_log.sh") | crontab -
    echo "📡 Авто-пуш логов настроен в ${GITHUB_REPO}"
fi

IP=$(curl -s ifconfig.me || hostname -I | awk '{print $1}')

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ Комната готова"
echo ""
echo "🔑 ТВОЯ ССЫЛКА:"
echo "   http://${IP}:${PORT}/?${ROOM_ALIAS}"
echo ""
echo "📝 Провайдер: ${PROVIDER} | Модель: ${MODEL}"
if [ -n "$GITHUB_TOKEN" ] && [ -n "$GITHUB_REPO" ]; then
    echo "📡 Логи пушатся в: https://github.com/${GITHUB_REPO}"
fi
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
