#!/bin/bash
set -e

# === VOID INSTALLER ===
INSTALL_DIR="/opt/void"
ENV_BACKUP="/opt/void.env.backup"
REPO_URL="https://github.com/dimko33-lang/void.git"

echo "==> Void Installation"

# Root check
if [ "$EUID" -ne 0 ]; then 
    echo "Error: Run as root"
    exit 1
fi

# Dependencies
apt update
apt install -y python3 python3-venv python3-pip git curl

# User
id void-agent &>/dev/null || useradd -m -s /bin/bash void-agent

# Clone / Pull
if [ ! -d "$INSTALL_DIR" ]; then
    git clone "$REPO_URL" "$INSTALL_DIR"
else
    cd "$INSTALL_DIR"
    git pull
fi

cd "$INSTALL_DIR"

# === UNKILLABLE .ENV LOGIC ===
if [ -f "$ENV_BACKUP" ]; then
    echo "==> Using saved keys from $ENV_BACKUP"
    cp "$ENV_BACKUP" .env
else
    echo "==> First run. Enter API keys (press Enter to skip):"
    read -p "GROQ_API_KEY: " GROQ_KEY
    read -p "KIMI_API_KEY: " KIMI_KEY
    read -p "OPENROUTER_API_KEY: " OPENROUTER_KEY

    cat > .env << EOF
GROQ_API_KEY=${GROQ_KEY}
KIMI_API_KEY=${KIMI_KEY}
OPENROUTER_API_KEY=${OPENROUTER_KEY}
DEFAULT_PROVIDER=groq
DEFAULT_MODEL=moonshotai/kimi-k2-instruct-0905
HOST=0.0.0.0
PORT=80
EOF
    # Save backup outside project dir
    cp .env "$ENV_BACKUP"
    chmod 600 "$ENV_BACKUP"
fi

chmod 600 .env
# === END UNKILLABLE LOGIC ===

# Alias
ALIAS_CODE=$(python3 -c "import secrets; print(secrets.token_hex(6))")
echo "-void-${ALIAS_CODE}" > void_alias.txt

# Permissions
chown root:root *.py 2>/dev/null || true
chmod 644 *.py 2>/dev/null || true
mkdir -p voids
chown -R void-agent:void-agent voids
chmod 755 voids

# Python venv
python3 -m venv venv
source venv/bin/activate
pip install --upgrade pip
pip install -r requirements.txt

# Systemd service
cat > /etc/systemd/system/void.service << EOF
[Unit]
Description=Void
After=network.target

[Service]
User=root
WorkingDirectory=$INSTALL_DIR
Environment="PATH=$INSTALL_DIR/venv/bin"
ExecStart=$INSTALL_DIR/venv/bin/python $INSTALL_DIR/room.py
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable void
systemctl restart void

IP=$(curl -s ifconfig.me || hostname -I | awk '{print $1}')
ALIAS=$(cat void_alias.txt)

echo ""
echo "=========================================="
echo "Void is ready"
echo "URL: http://${IP}:80/?${ALIAS}"
echo "Provider: groq / moonshotai/kimi-k2-instruct-0905"
echo "=========================================="
