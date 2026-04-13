#!/bin/bash
set -euo pipefail

ROLE="${1:-primary}"
ENV_FILE="${2:-/etc/health-ai/cloudflared-${ROLE}.env}"
SERVICE_NAME="${SERVICE_NAME:-cloudflared-health-${ROLE}}"
APP_SERVICE_NAME="${APP_SERVICE_NAME:-vital-command}"
RUN_AS_USER="${RUN_AS_USER:-${SUDO_USER:-$(id -un)}}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
WORKDIR="${WORKDIR:-$PROJECT_DIR}"
RUN_SCRIPT="${WORKDIR}/scripts/run-cloudflared-tunnel.sh"

if [ ! -f "$ENV_FILE" ]; then
  echo "Cloudflared env file not found: $ENV_FILE" >&2
  exit 1
fi

if ! grep -q '^TUNNEL_TOKEN=' "$ENV_FILE"; then
  echo "Cloudflared env file must contain TUNNEL_TOKEN=..." >&2
  exit 1
fi

if [ ! -x "$RUN_SCRIPT" ]; then
  echo "Cloudflared run script not found or not executable: $RUN_SCRIPT" >&2
  exit 1
fi

sudo tee "/etc/systemd/system/${SERVICE_NAME}.service" >/dev/null <<EOF
[Unit]
Description=Health AI Cloudflare Tunnel (${ROLE})
After=network-online.target ${APP_SERVICE_NAME}.service
Wants=network-online.target

[Service]
Type=simple
User=${RUN_AS_USER}
WorkingDirectory=${WORKDIR}
EnvironmentFile=${ENV_FILE}
ExecStart=${RUN_SCRIPT}
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now "${SERVICE_NAME}.service"
sudo systemctl status "${SERVICE_NAME}.service" --no-pager -l
