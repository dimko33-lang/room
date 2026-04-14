#!/bin/bash
set -e

echo "🧱 Восстановление Empty Room из бекапа..."

INSTALL_DIR="/opt/empty-room"

if [ "$EUID" -ne 0 ]; then 
    echo "❌ Запусти от root"
    exit 1
fi

# Останавливаем старую комнату
systemctl stop empty-room 2>/dev/null || true

# Удаляем старую папку
rm -rf "$INSTALL_DIR"

# Клонируем репозиторий и достаём бекап
echo "📦 Скачиваю бекап..."
git clone https://github.com/dimko33-lang/room.git /tmp/room-backup
cp /tmp/room-backup/backups/empty-room-backup-latest.tar.gz /tmp/backup.tar.gz
rm -rf /tmp/room-backup

# Распаковываем
mkdir -p "$INSTALL_DIR"
tar -xzf /tmp/backup.tar.gz -C "$INSTALL_DIR"
rm /tmp/backup.tar.gz

# Права
chown root:root "$INSTALL_DIR/room.py" "$INSTALL_DIR/agent.py" 2>/dev/null || true
chmod 644 "$INSTALL_DIR/room.py" "$INSTALL_DIR/agent.py" 2>/dev/null || true
chown -R my-agent:my-agent "$INSTALL_DIR/rooms"
chmod 755 "$INSTALL_DIR/rooms"

# Создаём пользователя, если нет
id my-agent &>/dev/null || useradd -m -s /bin/bash my-agent

# Python окружение
cd "$INSTALL_DIR"
python3 -m venv venv
source venv/bin/activate
pip install --upgrade pip
pip install -r requirements.txt 2>/dev/null || pip install flask requests python-dotenv

# Systemd сервис
cat > /etc/systemd/system/empty-room.service << EOF
[Unit]
Description=Empty Room
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
systemctl enable empty-room
systemctl restart empty-room

IP=$(curl -s ifconfig.me || hostname -I | awk '{print $1}')
ALIAS=$(cat "$INSTALL_DIR/room_alias.txt")

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ Комната восстановлена"
echo ""
echo "🔑 ТВОЯ ССЫЛКА:"
echo "   http://${IP}:80/?${ALIAS}"
echo ""
echo "📝 Она вернулась. Со всеми слезами, снами и файлами."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
