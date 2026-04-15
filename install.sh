#!/bin/bash
set -e

# Colors
GREEN='\033[0;32m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m'

# Progress bar
progress() {
    local current=$1
    local total=$2
    local prefix=$3
    local width=30
    local percent=$((current * 100 / total))
    local filled=$((width * current / total))
    local empty=$((width - filled))
    
    printf "\r${CYAN}%-12s${NC} [" "$prefix"
    printf "%${filled}s" | tr ' ' '='
    printf "%${empty}s" | tr ' ' ' '
    printf "] ${WHITE}%3d%%${NC}" "$percent"
}

clear
echo -e "${WHITE}Room :: Installation${NC}"
echo ""

# VENV
echo -e "${CYAN}VENV${NC}      Creating..."
if [ ! -d "venv" ]; then
    python3 -m venv venv 2>/dev/null
fi
echo -e "\r${GREEN}VENV${NC}      Created        [==============================] 100%"
source venv/bin/activate

# PIP
echo -e "${CYAN}PIP${NC}       Upgrading..."
for i in {1..10}; do
    progress $i 10 "PIP"
    sleep 0.1
done
pip install --upgrade pip --quiet 2>/dev/null
echo -e "\r${GREEN}PIP${NC}       Upgraded        [==============================] 100%"

# PACKAGES
echo ""
echo -e "${CYAN}PACKAGES${NC}  Installing openai, gradio, python-dotenv"
pip install openai gradio python-dotenv --quiet 2>/dev/null &
PIP_PID=$!

for i in {1..20}; do
    if kill -0 $PIP_PID 2>/dev/null; then
        progress $i 20 "PACKAGES"
        sleep 0.3
    else
        progress 20 20 "PACKAGES"
        break
    fi
done
wait $PIP_PID
echo -e "\r${GREEN}PACKAGES${NC}  Installed       [==============================] 100%"

# API Keys
echo ""
echo ""
echo -e "${WHITE}Enter API keys (press Enter to skip):${NC}"
echo ""

read -p "OPENAI_API_KEY: " API_KEY
read -p "OPENAI_BASE_URL: " BASE_URL
read -p "MODEL_NAME: " MODEL_NAME

# Create .env
cat > .env << EOF
OPENAI_API_KEY=${API_KEY}
OPENAI_BASE_URL=${BASE_URL}
MODEL_NAME=${MODEL_NAME}
EOF

# Done
clear
echo ""
echo ""
echo -e "    ${WHITE}http://127.0.0.1:7860${NC}"
echo ""
echo -e "    Provider: ${GREEN}${BASE_URL:-not set}${NC}"
echo -e "    Model:    ${GREEN}${MODEL_NAME:-not set}${NC}"
echo ""
