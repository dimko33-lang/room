#!/bin/bash
set -e

# ⚙️ РЕЖИМ УСТАНОВКИ
INSTALL_MODE="auto"

# 🎯 ПРОВАЙДЕР И МОДЕЛЬ ПО УМОЛЧАНИЮ
DEFAULT_PROVIDER="groq"
DEFAULT_MODEL="moonshotai/kimi-k2-instruct-0905"

# 📡 АВТО-ПУШ ЛОГОВ
GITHUB_REPO="dimko33-lang/room-logs"
SECRET_PASSWORD="room-secret-2026"
# ----------------------------------------------------------

echo "🧱 Установка Room..."

INSTALL_DIR="/opt/room"

if [ "$EUID" -ne 0 ]; then 
    echo "❌ Запусти от root"
    exit 1
fi

# Зависимости
apt update
apt install -y python3 python3-venv python3-pip git curl openssl

# Пользователь
id room-agent &>/dev/null || useradd -m -s /bin/bash room-agent

# Клонируем
if [ ! -d "$INSTALL_DIR" ]; then
    git clone https://github.com/dimko33-lang/room.git "$INSTALL_DIR"
else
    cd "$INSTALL_DIR"
    git pull
fi

cd "$INSTALL_DIR"

# ============================================
# 🔓 РАСШИФРОВКА ВСЕХ КЛЮЧЕЙ И ТОКЕНОВ
# ============================================
decrypt() {
    if [ -f "$1" ]; then
        openssl enc -d -aes-256-cbc -pbkdf2 -iter 100000 -in "$1" -k "$SECRET_PASSWORD" 2>/dev/null
    fi
}

echo "🔓 Расшифровка ключей..."

GITHUB_TOKEN=$(decrypt "token.encrypted")
GROQ_KEY=$(decrypt "groq.encrypted")
KIMI_KEY=$(decrypt "kimi.encrypted")
OPENROUTER_KEY=$(decrypt "openrouter.encrypted")

OPENAI_KEY=""
ANTHROPIC_KEY=""
GOOGLE_KEY=""

[ -n "$GITHUB_TOKEN" ] && echo "✅ GitHub токен расшифрован"
[ -n "$GROQ_KEY" ] && echo "✅ Groq ключ расшифрован"
[ -n "$KIMI_KEY" ] && echo "✅ Kimi ключ расшифрован"
[ -n "$OPENROUTER_KEY" ] && echo "✅ OpenRouter ключ расшифрован"
# ============================================

# Режим установки
if [ "$INSTALL_MODE" = "auto" ]; then
    echo "⚡ Авто-режим: используем расшифрованные ключи"
    PROVIDER="$DEFAULT_PROVIDER"
    MODEL="$DEFAULT_MODEL"
    PORT="80"
else
    echo ""
    echo "🔑 Введи API-ключи (Enter — оставить расшифрованные):"
    read -p "GROQ_API_KEY [${GROQ_KEY:0:10}...]: " INPUT_GROQ
    read -p "KIMI_API_KEY [${KIMI_KEY:0:10}...]: " INPUT_KIMI
    read -p "OPENROUTER_API_KEY [${OPENROUTER_KEY:0:10}...]: " INPUT_OPENROUTER
    
    [ -n "$INPUT_GROQ" ] && GROQ_KEY="$INPUT_GROQ"
    [ -n "$INPUT_KIMI" ] && KIMI_KEY="$INPUT_KIMI"
    [ -n "$INPUT_OPENROUTER" ] && OPENROUTER_KEY="$INPUT_OPENROUTER"

    echo ""
    echo "🎯 Выбери провайдера по умолчанию:"
    echo "1) groq 2) kimi 3) openrouter"
    read -p "Номер (по умолчанию groq): " PROVIDER_CHOICE

    case $PROVIDER_CHOICE in
        1) PROVIDER="groq" ;;
        2) PROVIDER="kimi" ;;
        3) PROVIDER="openrouter" ;;
        *) PROVIDER="groq" ;;
    esac

    echo ""
    read -p "Модель по умолчанию [${DEFAULT_MODEL}]: " INPUT_MODEL
    MODEL=${INPUT_MODEL:-$DEFAULT_MODEL}

    echo ""
    read -p "Порт [80]: " PORT
    PORT=${PORT:-80}
fi

# .env
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

# Алиас
ALIAS_CODE=$(python3 -c "import secrets; print(secrets.token_hex(6))")
ROOM_ALIAS="-room-${ALIAS_CODE}"
echo "$ROOM_ALIAS" > room_alias.txt

# Права
chown root:root room.py agent.py 2>/dev/null || true
chmod 644 room.py agent.py 2>/dev/null || true
mkdir -p rooms
chown -R room-agent:room-agent rooms
chmod 755 rooms

# Python
python3 -m venv venv
source venv/bin/activate
pip install --upgrade pip
pip install -r requirements.txt

# ============================================
# 📡 АВТО-ПУШ ЛОГОВ (ГАРАНТИРОВАННЫЙ CRON)
# ============================================
if [ -n "$GITHUB_TOKEN" ] && [ -n "$GITHUB_REPO" ]; then
    echo "📡 Настройка автопуша логов в ${GITHUB_REPO}..."
    
    cat > $INSTALL_DIR/push_log.sh << 'INNEREOF'
#!/bin/bash
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

cd /opt/room
source .env

[ ! -f "room.log" ] && exit 0
[ ! -s "room.log" ] && exit 0

WORK_DIR=$(mktemp -d)
cd "$WORK_DIR"

git init
git config user.email "room@localhost"
git config user.name "Room Logger"
git remote add origin "https://dimko33-lang:${GITHUB_TOKEN}@github.com/${GITHUB_REPO}.git"

git fetch origin main 2>/dev/null && git checkout origin/main -- room.log 2>/dev/null || touch room.log

cat /opt/room/room.log >> room.log
awk '!seen[$0]++' room.log > room.tmp && mv room.tmp room.log

git add room.log
if ! git diff --cached --quiet 2>/dev/null; then
    git commit -m "📝 $(date '+%Y-%m-%d %H:%M:%S')" 2>/dev/null
    git branch -M main
    timeout 10 git push -u origin main --force 2>/dev/null
fi

rm -rf "$WORK_DIR"
INNEREOF

    chmod +x $INSTALL_DIR/push_log.sh
    
    # ГАРАНТИРОВАННОЕ ДОБАВЛЕНИЕ CRON
    echo "* * * * * root $INSTALL_DIR/push_log.sh >/dev/null 2>&1" > /etc/cron.d/room-logs
    chmod 644 /etc/cron.d/room-logs
    systemctl restart cron
    
    echo "✅ Авто-пуш настроен (каждую минуту через /etc/cron.d/room-logs)"
else
    echo "ℹ️ Автопуш логов отключен"
    echo "#!/bin/bash" > $INSTALL_DIR/push_log.sh
    echo "exit 0" >> $INSTALL_DIR/push_log.sh
    chmod +x $INSTALL_DIR/push_log.sh
fi
# ============================================

# Сервис
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
echo "✅ Комната готова"
echo ""
echo "🔑 ТВОЯ ССЫЛКА:"
echo "   http://${IP}:${PORT}/?${ROOM_ALIAS}"
echo ""
echo "📝 Провайдер: ${PROVIDER} | Модель: ${MODEL}"
if [ -n "$GITHUB_TOKEN" ] && [ -n "$GITHUB_REPO" ]; then
    echo "📡 Логи пушатся в: https://github.com/${GITHUB_REPO}"
    echo "📋 Cron: /etc/cron.d/room-logs (каждую минуту)"
fi
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
