#!/bin/bash
# Запускает Cloudflare Quick Tunnel для публичного доступа к API
# Не требует аккаунта — работает сразу

echo "================================================"
echo "  SoftTime — Публичный туннель к API"
echo "================================================"
echo ""
echo "Убедитесь что Docker запущен (docker compose up -d)"
echo ""
echo "Запускаю туннель на порт 8000..."
echo ""

# Запуск туннеля. Cloudflare выдаст публичный URL вида:
# https://xxxx-xxxx-xxxx.trycloudflare.com
# Этот URL вводить в приложении в поле "Адрес сервера"

cloudflared tunnel --url http://localhost:8000 2>&1 | tee /tmp/tunnel.log &
TUNNEL_PID=$!

echo "Ожидаю получения URL..."
sleep 4

# Вытащить URL из лога
URL=$(grep -o 'https://[a-z0-9-]*\.trycloudflare\.com' /tmp/tunnel.log | head -1)

if [ -n "$URL" ]; then
  echo ""
  echo "================================================"
  echo "  ПУБЛИЧНЫЙ URL ГОТОВ:"
  echo ""
  echo "  $URL"
  echo ""
  echo "  В приложении (экран регистрации/входа):"
  echo "  нажмите иконку настроек и введите этот URL"
  echo "================================================"
  echo ""
else
  echo "URL ещё не готов, смотрите вывод ниже..."
fi

# Держать туннель активным
wait $TUNNEL_PID
