#!/bin/bash
set -e  # Остановка при ошибке

echo "Настройка FillSteam API на 84.54.58.137"
echo "Домен: api.fillsteam.online"
echo "Стек: Python + FastAPI + Caddy + systemd"
echo "----------------------------------------"

# 1. Обновление системы
echo "[1/7] Обновление системы..."
apt update && apt upgrade -y

# 2. Установка зависимостей
echo "[2/7] Установка Python, Git, UFW..."
apt install -y python3 python3-pip python3-venv git curl ufw

# 3. Создание проекта
echo "[3/7] Создание проекта..."
mkdir -p /root/fillsteam-api && cd /root/fillsteam-api

if [ ! -d "venv" ]; then
    python3 -m venv venv
fi
source venv/bin/activate
pip install --upgrade pip
pip install fastapi uvicorn

# 4. Создание main.py
echo "[4/7] Создание API (main.py)..."
cat > main.py << 'EOF'
from fastapi import FastAPI
from pydantic import BaseModel

app = FastAPI(title="FillSteam API", version="1.0")

class Message(BaseModel):
    text: str

@app.get("/")
def home():
    return {"status": "ok", "message": "API работает на fillsteam.online"}

@app.get("/api/hello")
def hello():
    return {"hello": "world", "from": "84.54.58.137"}

@app.post("/api/echo")
def echo(msg: Message):
    return {"echo": msg.text.upper()}
EOF

# 5. Systemd сервис
echo "[5/7] Создание systemd сервиса..."
cat > /etc/systemd/system/fillsteam-api.service << 'EOF'
[Unit]
Description=FillSteam FastAPI
After=network.target

[Service]
User=root
WorkingDirectory=/root/fillsteam-api
Environment="PATH=/root/fillsteam-api/venv/bin"
ExecStart=/root/fillsteam-api/venv/bin/uvicorn main:app --host 0.0.0.0 --port 8000
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reexec
systemctl enable fillsteam-api
systemctl restart fillsteam-api

# 6. Caddy (авто-HTTPS)
echo "[6/7] Установка Caddy..."
apt install -y debian-keyring debian-archive-keyring apt-transport-https
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | tee /etc/apt/sources.list.d/caddy-stable.list
apt update
apt install caddy -y

# Caddyfile
cat > /etc/caddy/Caddyfile << 'EOF'
api.fillsteam.online {
    reverse_proxy localhost:8000
}
EOF

systemctl restart caddy
systemctl enable caddy

# 7. Фаервол
echo "[7/7] Настройка UFW..."
ufw allow 22
ufw allow 80
ufw allow 443
ufw --force enable

echo "========================================="
echo "ГОТОВО!"
echo ""
echo "Проверь через 1-2 минуты:"
echo "   https://api.fillsteam.online"
echo "   https://api.fillsteam.online/docs"
echo ""
echo "Логи:"
echo "   journalctl -u fillsteam-api -f"
echo "   journalctl -u caddy -f"
echo ""
echo "Обновление кода:"
echo "   cd /root/fillsteam-api && git pull && systemctl restart fillsteam-api"
echo "========================================="
