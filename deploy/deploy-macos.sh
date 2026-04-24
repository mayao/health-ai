#!/bin/bash
set -euo pipefail

# ============================================================
# Health AI 主站部署脚本（macOS 目标机）
# 用法:
#   DEPLOY_ENV_FILE=deploy/.env.primary.local ./deploy/deploy-macos.sh [user@host]
# ============================================================

TARGET="${1:-Apple@10.8.144.16}"
REMOTE_DIR_NAME="${REMOTE_DIR_NAME:-vital-command}"
REMOTE_PORT="${REMOTE_PORT:-3001}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
DEFAULT_ENV_FILE="$PROJECT_DIR/deploy/.env.primary.local"
DEPLOY_ENV_FILE="${DEPLOY_ENV_FILE:-$DEFAULT_ENV_FILE}"

cd "$PROJECT_DIR"

if [ ! -f "$DEPLOY_ENV_FILE" ]; then
  echo "Missing primary env file: $DEPLOY_ENV_FILE" >&2
  exit 1
fi

echo "╔══════════════════════════════════════════╗"
echo "║   Health AI macOS 主站部署               ║"
echo "║   目标: $TARGET:~/$REMOTE_DIR_NAME (port $REMOTE_PORT)"
echo "╚══════════════════════════════════════════╝"
echo ""

echo "▶ [1/4] 构建 Next.js standalone..."
PATH="/opt/homebrew/opt/node@22/bin:$PATH" npm run build
echo "  ✅ 构建完成"

echo ""
echo "▶ [2/4] 初始化远程目录..."
ssh "$TARGET" "mkdir -p ~/$REMOTE_DIR_NAME/data ~/$REMOTE_DIR_NAME/.next/standalone ~/$REMOTE_DIR_NAME/.next/static ~/$REMOTE_DIR_NAME/migrations ~/$REMOTE_DIR_NAME/scripts ~/$REMOTE_DIR_NAME/deploy ~/$REMOTE_DIR_NAME/logs"
echo "  ✅ 目录就绪"

echo ""
echo "▶ [3/4] 同步文件到远程..."
# Do not overwrite runtime SQLite data on remote during code deploy.
rsync -az --delete --exclude "data/" .next/standalone/ "$TARGET:~/$REMOTE_DIR_NAME/.next/standalone/"
rsync -az --delete .next/static/ "$TARGET:~/$REMOTE_DIR_NAME/.next/static/"
rsync -az --delete migrations/ "$TARGET:~/$REMOTE_DIR_NAME/migrations/"
rsync -az --delete scripts/ "$TARGET:~/$REMOTE_DIR_NAME/scripts/"
rsync -az "$DEPLOY_ENV_FILE" "$TARGET:~/$REMOTE_DIR_NAME/.env"
rsync -az deploy/PUBLIC_ACCESS.md "$TARGET:~/$REMOTE_DIR_NAME/deploy/PUBLIC_ACCESS.md"
rsync -az deploy/install-health-app-launchd.sh "$TARGET:~/$REMOTE_DIR_NAME/deploy/install-health-app-launchd.sh"
rsync -az deploy/install-cloudflared-backup-launchd.sh "$TARGET:~/$REMOTE_DIR_NAME/deploy/install-cloudflared-backup-launchd.sh"
rsync -az deploy/install-primary-tunnel-guard-launchd.sh "$TARGET:~/$REMOTE_DIR_NAME/deploy/install-primary-tunnel-guard-launchd.sh"
[ -d public ] && rsync -az --delete public/ "$TARGET:~/$REMOTE_DIR_NAME/public/"
ssh "$TARGET" "rm -f ~/$REMOTE_DIR_NAME/server.js"
ssh "$TARGET" "chmod +x ~/$REMOTE_DIR_NAME/scripts/run-health-server.sh ~/$REMOTE_DIR_NAME/scripts/start-health-server.sh ~/$REMOTE_DIR_NAME/scripts/stop-health-server.sh ~/$REMOTE_DIR_NAME/scripts/ensure-primary-tunnel-healthy.sh ~/$REMOTE_DIR_NAME/deploy/install-health-app-launchd.sh ~/$REMOTE_DIR_NAME/deploy/install-cloudflared-backup-launchd.sh ~/$REMOTE_DIR_NAME/deploy/install-primary-tunnel-guard-launchd.sh"
echo "  ✅ 文件同步完成"

echo ""
echo "▶ [4/4] 启动主站服务..."
ssh "$TARGET" "cd ~/$REMOTE_DIR_NAME && ./deploy/install-health-app-launchd.sh && ./deploy/install-primary-tunnel-guard-launchd.sh && sleep 2 && curl -fsS http://127.0.0.1:$REMOTE_PORT/api/health"

echo ""
echo "╔══════════════════════════════════════════╗"
echo "║   ✅ macOS 主站部署完成                  ║"
echo "║   服务地址: http://${TARGET##*@}:$REMOTE_PORT     ║"
echo "╚══════════════════════════════════════════╝"
