#!/bin/bash
set -euo pipefail

# ============================================================
# Health AI 主站部署脚本
# 用法:
#   DEPLOY_ENV_FILE=deploy/.env.primary.local ./deploy/deploy.sh [user@host]
# 示例:
#   cp deploy/env/health-primary.env.example deploy/.env.primary.local
#   DEPLOY_ENV_FILE=deploy/.env.primary.local ./deploy/deploy.sh xmly@10.8.144.16
# ============================================================

TARGET=${1:-"xmly@10.8.144.16"}
REMOTE_DIR=${REMOTE_DIR:-"/opt/vital-command"}
REMOTE_PORT=${REMOTE_PORT:-3001}
SERVICE_NAME=${SERVICE_NAME:-"vital-command"}
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
DEFAULT_ENV_FILE="$PROJECT_DIR/deploy/.env.primary.local"
DEPLOY_ENV_FILE="${DEPLOY_ENV_FILE:-$DEFAULT_ENV_FILE}"
RUN_AS_USER="${RUN_AS_USER:-}"

cd "$PROJECT_DIR"

if [ ! -f "$DEPLOY_ENV_FILE" ]; then
  echo "❌ 缺少主站环境文件: $DEPLOY_ENV_FILE"
  echo "   先执行：cp deploy/env/health-primary.env.example deploy/.env.primary.local"
  echo "   然后填写真实域名、JWT secret 和 LLM 密钥。"
  exit 1
fi

if [ -z "$RUN_AS_USER" ]; then
  if [[ "$TARGET" == *@* ]]; then
    RUN_AS_USER="${TARGET%@*}"
  else
    RUN_AS_USER="$(id -un)"
  fi
fi

SERVICE_TMP="$(mktemp)"
cleanup() {
  rm -f "$SERVICE_TMP"
}
trap cleanup EXIT

sed \
  -e "s|__RUN_AS_USER__|$RUN_AS_USER|g" \
  -e "s|__WORKDIR__|$REMOTE_DIR|g" \
  "$PROJECT_DIR/deploy/vital-command.service" > "$SERVICE_TMP"

echo "╔══════════════════════════════════════════╗"
echo "║   Health AI 主站部署                     ║"
echo "║   目标: $TARGET:$REMOTE_DIR (port $REMOTE_PORT)"
echo "╚══════════════════════════════════════════╝"
echo ""

# ---- Step 1: Build ----
echo "▶ [1/5] 构建 Next.js standalone..."
PATH="/opt/homebrew/opt/node@22/bin:$PATH" npm run build
echo "  ✅ 构建完成"

# ---- Step 2: Test SSH ----
echo ""
echo "▶ [2/5] 测试 SSH 连接..."
ssh -o ConnectTimeout=5 -o BatchMode=yes "$TARGET" "echo '  ✅ SSH 连接成功'" 2>/dev/null || {
    echo "  ❌ 无法连接到 $TARGET"
    echo "  请确保："
    echo "    1. 目标机已开机且在同一网段"
    echo "    2. 已配置 SSH 密钥（ssh-copy-id $TARGET）"
    echo "    3. 目标机已安装 Node.js 22+"
    echo ""
    echo "  手动部署步骤："
    echo "    scp -r .next/standalone/ $TARGET:$REMOTE_DIR/"
    echo "    scp -r .next/static/ $TARGET:$REMOTE_DIR/.next/static/"
    echo "    scp -r migrations/ $TARGET:$REMOTE_DIR/migrations/"
    echo "    scp -r scripts/ $TARGET:$REMOTE_DIR/scripts/"
    echo "    scp $DEPLOY_ENV_FILE $TARGET:$REMOTE_DIR/.env"
    echo "    ssh $TARGET 'cd $REMOTE_DIR && ./scripts/run-health-server.sh'"
    exit 1
}

# ---- Step 3: Setup remote directory ----
echo ""
echo "▶ [3/5] 初始化远程目录..."
ssh "$TARGET" "sudo mkdir -p $REMOTE_DIR/data $REMOTE_DIR/.next/standalone $REMOTE_DIR/.next/static $REMOTE_DIR/migrations $REMOTE_DIR/scripts $REMOTE_DIR/deploy/env && sudo chown -R $RUN_AS_USER $REMOTE_DIR"
echo "  ✅ 目录就绪"

# ---- Step 4: Sync files ----
echo ""
echo "▶ [4/5] 同步文件到远程..."
rsync -az --delete .next/standalone/ "$TARGET:$REMOTE_DIR/.next/standalone/"
rsync -az --delete .next/static/ "$TARGET:$REMOTE_DIR/.next/static/"
rsync -az --delete migrations/ "$TARGET:$REMOTE_DIR/migrations/"
rsync -az --delete scripts/ "$TARGET:$REMOTE_DIR/scripts/"
rsync -az --delete deploy/env/ "$TARGET:$REMOTE_DIR/deploy/env/"
rsync -az deploy/PUBLIC_ACCESS.md "$TARGET:$REMOTE_DIR/deploy/PUBLIC_ACCESS.md"
rsync -az deploy/install-cloudflared-service.sh "$TARGET:$REMOTE_DIR/deploy/install-cloudflared-service.sh"
rsync -az deploy/install-cloudflared-backup-launchd.sh "$TARGET:$REMOTE_DIR/deploy/install-cloudflared-backup-launchd.sh"
rsync -az "$DEPLOY_ENV_FILE" "$TARGET:$REMOTE_DIR/.env"

[ -d public ] && rsync -az --delete public/ "$TARGET:$REMOTE_DIR/public/"
ssh "$TARGET" "rm -f $REMOTE_DIR/server.js"

# Sync systemd service
ssh "$TARGET" "chmod +x $REMOTE_DIR/scripts/run-health-server.sh $REMOTE_DIR/scripts/run-cloudflared-tunnel.sh $REMOTE_DIR/deploy/install-cloudflared-service.sh"
ssh "$TARGET" "sudo cp /dev/stdin /etc/systemd/system/${SERVICE_NAME}.service" < "$SERVICE_TMP"
echo "  ✅ 文件同步完成"

# ---- Step 5: Restart service ----
echo ""
echo "▶ [5/5] 重启服务..."
ssh "$TARGET" "sudo systemctl daemon-reload && sudo systemctl enable $SERVICE_NAME && sudo systemctl restart $SERVICE_NAME && sleep 2 && sudo systemctl status $SERVICE_NAME --no-pager -l"

echo ""
echo "╔══════════════════════════════════════════╗"
echo "║   ✅ 部署完成!                           ║"
echo "║   服务地址: http://${TARGET##*@}:$REMOTE_PORT     ║"
echo "╚══════════════════════════════════════════╝"
echo ""
echo "常用命令："
echo "  ssh $TARGET 'curl -fsS http://127.0.0.1:$REMOTE_PORT/api/health'   # 健康检查"
echo "  ssh $TARGET 'sudo systemctl status $SERVICE_NAME'   # 查看状态"
echo "  ssh $TARGET 'sudo journalctl -u $SERVICE_NAME -f'   # 查看日志"
echo "  ssh $TARGET 'cd $REMOTE_DIR && sed -n \"1,220p\" deploy/PUBLIC_ACCESS.md'   # 查看 tunnel 配置步骤"
