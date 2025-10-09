#!/usr/bin/env bash
set -euo pipefail

# This script attempts to ensure webhook.js is running and sets up a system service (Linux) or prints guidance for Windows.
ROOT=$(dirname "${BASH_SOURCE[0]}")/..
WEBHOOK_JS="$ROOT/suma-webhook/webhook.js"

require_cmd() { command -v "$1" >/dev/null 2>&1 || return 1; }

if [ ! -f "$WEBHOOK_JS" ]; then echo "webhook.js not found at $WEBHOOK_JS"; exit 1; fi

if require_cmd pm2; then
  echo "pm2 found, using pm2 to run webhook.js"
  pm2 delete suma-webhook >/dev/null 2>&1 || true
  pm2 start "$WEBHOOK_JS" --name suma-webhook --restart-delay 1000 --max-memory-restart 200M
  pm2 save || true
  if require_cmd systemctl; then
    pm2 startup systemd -u $(whoami) --hp "$HOME" || true
  fi
  echo "pm2 configured to run webhook.js"
  exit 0
fi

# fallback: systemd unit on Linux
if [ "$(uname -s)" = "Linux" ]; then
  SERVICE_FILE="/etc/systemd/system/suma-webhook.service"
  if [ ! -f "$SERVICE_FILE" ]; then
    echo "Creating systemd service for webhook"
    sudo tee "$SERVICE_FILE" >/dev/null <<EOF
[Unit]
Description=Suma Webhook Service
After=network.target

[Service]
Type=simple
ExecStart=$(command -v node) $WEBHOOK_JS
Restart=always
User=$(whoami)

[Install]
WantedBy=multi-user.target
EOF
    sudo systemctl daemon-reload
    sudo systemctl enable --now suma-webhook
    echo "systemd service created and started"
  else
    echo "systemd service already exists: $SERVICE_FILE"
  fi
  exit 0
fi

# Windows guidance
cat <<'EOF'
webhook.js found. On Windows, please run it using pm2 or Task Scheduler.
Suggested steps:
 - Install Node.js and pm2.
 - Run: pm2 start "<path>\webhook.js" --name suma-webhook --restart-delay 1000 --max-memory-restart 200M
 - Then: pm2 save
 - Or create a Task Scheduler entry to run node at startup under SYSTEM.
EOF
