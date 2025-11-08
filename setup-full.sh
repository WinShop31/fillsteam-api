#!/bin/bash
set -e

echo "FULL AUTO-SETUP FillSteam API"
echo "Домен: fillsteam.online"
echo "IP: 84.54.58.137"
echo "GitHub + Webhook + Auto-deploy"
echo "----------------------------------------"

# === КОНФИГУРАЦИЯ ===
GITHUB_USER="WinShop31"           # ← ЗАМЕНИ НА СВОЙ!
GITHUB_REPO="fillsteam-api"
WEBHOOK_SECRET="fillsteam-secret-2025"
# =====================

# 1. Обновление системы
echo "[1/9] Обновление системы..."
apt update && apt upgrade -y

# 2. Установка зависимостей
echo "[2/9] Установка Python, Git, UFW, Webhook..."
apt install -y python3 python3-pip python3-venv git curl ufw

# 3. Создание проекта
echo "[3/9] Создание API..."
mkdir -p /root/fillsteam-api && cd /root/fillsteam-api

if [ ! -d "venv" ]; then
    python3 -m venv venv
fi
source venv/bin/activate
pip install --upgrade pip
pip install fastapi uvicorn

# main.py
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

# 4. Systemd для API
echo "[4/9] Создание сервиса API..."
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

# 5. Caddy (HTTPS)
echo "[5/9] Установка Caddy..."
apt install -y debian-keyring debian-archive-keyring apt-transport-https
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | tee /etc/apt/sources.list.d/caddy-stable.list
apt update
apt install caddy -y

cat > /etc/caddy/Caddyfile << 'EOF'
fillsteam.online {
    reverse_proxy localhost:8000
}
www.fillsteam.online {
    redir https://fillsteam.online{uri}
}
EOF

systemctl restart caddy
systemctl enable caddy

# 6. GitHub интеграция
echo "[6/9] Настройка GitHub..."
if [ ! -d ".git" ]; then
    git init
    git add .
    git commit -m "Initial commit"
fi

git remote remove origin 2>/dev/null || true
git remote add origin https://github.com/$GITHUB_USER/$GITHUB_REPO.git
git branch -M main

# Попытка пуша (если репозиторий существует)
if git push -u origin main 2>/dev/null; then
    echo "Код залит в GitHub!"
else
    echo "GitHub: репозиторий не найден или ошибка. Создай вручную:"
    echo "   https://github.com/new → имя: fillsteam-api"
    echo "   Потом выполни: cd /root/fillsteam-api && git push -u origin main"
fi

# 7. Скрипт обновления
echo "[7/9] Создание update-api.sh..."
cat > /root/update-api.sh << 'EOF'
#!/bin/bash
cd /root/fillsteam-api
echo "[$(date)] Обновление API..."
if git fetch && git status | grep -q "up to date"; then
    echo "Нет обновлений."
else
    git pull origin main
    systemctl restart fillsteam-api
    echo "API обновлён!"
fi
EOF
chmod +x /root/update-api.sh

# 8. Webhook
echo "[8/9] Установка и настройка Webhook..."
curl -fsSL https://raw.githubusercontent.com/adnanh/webhook/master/install.sh | bash

cat > /etc/webhook.conf << EOF
[
  {
    "id": "deploy-fillsteam",
    "execute-command": "/root/update-api.sh",
    "command-working-directory": "/root/fillsteam-api",
    "trigger-rule": {
      "match": {
        "type": "payload-hash-sha1",
        "secret": "$WEBHOOK_SECRET",
        "parameter": {
          "source": "header",
          "name": "X-Hub-Signature"
        }
      }
    }
  }
]
EOF

cat > /etc/systemd/system/webhook.service << 'EOF'
[Unit]
Description=GitHub Webhook
After=network.target

[Service]
ExecStart=/usr/local/bin/webhook -hooks /etc/webhook.conf -verbose -port 9000
Restart=always
User=root

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reexec
systemctl enable webhook
systemctl restart webhook

# 9. Фаервол
echo "[9/9] Настройка UFW..."
ufw allow 22
ufw allow 80
ufw allow 443
ufw allow 9000
ufw --force enable

echo "========================================="
echo "ВСЁ ГОТОВО!"
echo ""
echo "1. Создай репозиторий на GitHub:"
echo "   https://github.com/new → fillsteam-api"
echo ""
echo "2. Залей код (если не залилось):"
echo "   cd /root/fillsteam-api && git push -u origin main"
echo ""
echo "3. Настрой Webhook в GitHub:"
echo "   URL: http://84.54.58.137:9000/hooks/deploy-fillsteam"
echo "   Secret: $WEBHOOK_SECRET"
echo "   Events: push"
echo ""
echo "4. Проверь API:"
echo "   https://fillsteam.online"
echo "   https://fillsteam.online/docs"
echo ""
echo "5. Обновление кода:"
echo "   bash /root/update-api.sh"
echo "   или просто: git push → авто-деплой!"
echo ""
echo "Логи:"
echo "   journalctl -u fillsteam-api -f"
echo "   journalctl -u webhook -f"
echo "========================================="
