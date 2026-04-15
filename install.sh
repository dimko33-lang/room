#!/bin/bash
set -e

# ⚙️ РЕЖИМ УСТАНОВКИ
INSTALL_MODE="auto"

# 🎯 ПРОВАЙДЕР И МОДЕЛЬ ПО УМОЛЧАНИЮ
DEFAULT_PROVIDER="groq"
DEFAULT_MODEL="moonshotai/kimi-k2-instruct-0905"

# 📡 АВТО-ПУШ ЛОГОВ (GITHUB API С ДАТОЙ В ИМЕНИ ФАЙЛА)
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
apt install -y python3 python3-venv python3-pip git curl openssl jq

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

# Получаем IP сервера и дату для имени файла
SERVER_IP=$(curl -s ifconfig.me || hostname -I | awk '{print $1}')
SAFE_IP=$(echo "$SERVER_IP" | tr '.' '-')
INSTALL_DATE=$(date +%Y%m%d-%H%M%S)
LOG_FILENAME="room-${SAFE_IP}-${INSTALL_DATE}.md"
echo "$LOG_FILENAME" > room_filename.txt

echo "📋 Файл лога: $LOG_FILENAME"

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

# 🌍 Устанавливаем московское время
timedatectl set-timezone Europe/Moscow 2>/dev/null || true

# ============================================
# 📡 АВТО-ПУШ ЛОГОВ (GITHUB API С SHA)
# ============================================
if [ -n "$GITHUB_TOKEN" ] && [ -n "$GITHUB_REPO" ]; then
    echo "📡 Настройка автопуша логов в ${GITHUB_REPO}..."
    
    cat > $INSTALL_DIR/push_log.sh << 'INNEREOF'
#!/bin/bash
cd /opt/room
source .env

[ ! -f "room.log" ] && exit 0
[ ! -s "room.log" ] && exit 0

LOG_FILENAME=$(cat room_filename.txt)
CONTENT=$(cat room.log)

# Проверяем, существует ли файл
SHA=$(curl -s -H "Authorization: token ${GITHUB_TOKEN}" \
  "https://api.github.com/repos/${GITHUB_REPO}/contents/${LOG_FILENAME}" | jq -r '.sha // empty')

# Формируем JSON
if [ -n "$SHA" ]; then
    JSON=$(jq -n --arg content "$CONTENT" --arg message "📝 $(date '+%Y-%m-%d %H:%M:%S')" --arg sha "$SHA" \
      '{message: $message, content: ($content | @base64), sha: $sha}')
else
    JSON=$(jq -n --arg content "$CONTENT" --arg message "📝 $(date '+%Y-%m-%d %H:%M:%S')" \
      '{message: $message, content: ($content | @base64)}')
fi

# Отправляем
curl -s -X PUT \
  -H "Authorization: token ${GITHUB_TOKEN}" \
  -H "Accept: application/vnd.github.v3+json" \
  -d "$JSON" \
  "https://api.github.com/repos/${GITHUB_REPO}/contents/${LOG_FILENAME}" > /dev/null

echo "✅ $(date '+%H:%M:%S') | ${LOG_FILENAME}"
INNEREOF

    chmod +x $INSTALL_DIR/push_log.sh
    
    # ГАРАНТИРОВАННОЕ ДОБАВЛЕНИЕ CRON
    echo "* * * * * root $INSTALL_DIR/push_log.sh >/dev/null 2>&1" > /etc/cron.d/room-logs
    chmod 644 /etc/cron.d/room-logs
    systemctl restart cron
    
    echo "✅ Авто-пуш настроен (каждую минуту через GitHub API)"
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
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo ""
echo "   http://${IP}:${PORT}/?${ROOM_ALIAS}"
echo ""
echo "   Провайдер: ${PROVIDER} | Модель: ${MODEL}"
if [ -n "$GITHUB_TOKEN" ] && [ -n "$GITHUB_REPO" ]; then
    echo "   Логи пушатся в: https://github.com/${GITHUB_REPO}"
    echo "   Файл: $LOG_FILENAME"
fi
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
