#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
HOSTS_ENV_FILE="${HOSTS_ENV_FILE:-$PROJECT_DIR/deploy/.env.remote-hosts}"
PRIMARY_DEPLOY_ENV_FILE="${PRIMARY_DEPLOY_ENV_FILE:-$PROJECT_DIR/deploy/.env.primary.local}"
BACKUP_DEPLOY_ENV_FILE="${BACKUP_DEPLOY_ENV_FILE:-$PROJECT_DIR/deploy/.env.backup.local}"

if [ ! -f "$HOSTS_ENV_FILE" ]; then
  echo "❌ 缺少远端主机配置文件: $HOSTS_ENV_FILE" >&2
  echo "   可参考: deploy/env/remote-hosts.env.example" >&2
  exit 1
fi

if [ ! -f "$PRIMARY_DEPLOY_ENV_FILE" ]; then
  echo "❌ 缺少主站环境文件: $PRIMARY_DEPLOY_ENV_FILE" >&2
  exit 1
fi

if [ ! -f "$BACKUP_DEPLOY_ENV_FILE" ]; then
  echo "❌ 缺少备站环境文件: $BACKUP_DEPLOY_ENV_FILE" >&2
  exit 1
fi

source "$HOSTS_ENV_FILE"

PRIMARY_TARGET="${REMOTE_USER_PRIMARY}@${REMOTE_HOST_PRIMARY}"
BACKUP_TARGET="${REMOTE_USER_BACKUP}@${REMOTE_HOST_BACKUP}"

echo "==> 部署主站: $PRIMARY_TARGET"
DEPLOY_ENV_FILE="$PRIMARY_DEPLOY_ENV_FILE" "$PROJECT_DIR/deploy/deploy-macos.sh" "$PRIMARY_TARGET"

echo "==> 部署备站: $BACKUP_TARGET"
DEPLOY_ENV_FILE="$BACKUP_DEPLOY_ENV_FILE" "$PROJECT_DIR/deploy/deploy-macos.sh" "$BACKUP_TARGET"

echo "✅ 双机部署完成，已按 launchd 常驻模式启动。"
