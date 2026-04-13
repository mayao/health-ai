#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

PRIMARY_HOST="${PRIMARY_HOST:-Apple@10.8.144.16}"
PRIMARY_APP_DIR="${PRIMARY_APP_DIR:-~/vital-command}"
PRIMARY_NODE_BIN="${PRIMARY_NODE_BIN:-/opt/homebrew/opt/node@22/bin/node}"
PRIMARY_DB_REL_PATH="${PRIMARY_DB_REL_PATH:-data/health-system.sqlite}"
PRIMARY_SNAPSHOT_REL_PATH="${PRIMARY_SNAPSHOT_REL_PATH:-data/health-system.sync.snapshot.sqlite}"

LOCAL_DB_PATH="${LOCAL_DB_PATH:-$PROJECT_DIR/data/health-system.sqlite}"
LOCAL_SNAPSHOT_PATH="${LOCAL_SNAPSHOT_PATH:-$PROJECT_DIR/data/health-system.from-primary.sqlite}"

echo "==> [1/4] 在主服务器生成 SQLite 快照: $PRIMARY_HOST"
ssh "$PRIMARY_HOST" "cd $PRIMARY_APP_DIR && rm -f $PRIMARY_SNAPSHOT_REL_PATH && $PRIMARY_NODE_BIN -e \"const { DatabaseSync } = require('node:sqlite'); const db = new DatabaseSync('$PRIMARY_DB_REL_PATH'); db.exec(\\\"VACUUM INTO '$PRIMARY_SNAPSHOT_REL_PATH';\\\"); console.log('snapshot-ready');\""

echo "==> [2/4] 拉取快照到本地备站"
mkdir -p "$(dirname "$LOCAL_DB_PATH")"
scp "$PRIMARY_HOST:$PRIMARY_APP_DIR/$PRIMARY_SNAPSHOT_REL_PATH" "$LOCAL_SNAPSHOT_PATH"

echo "==> [3/4] 原子替换本地备站数据库"
if [ -f "$LOCAL_DB_PATH" ] && cmp -s "$LOCAL_SNAPSHOT_PATH" "$LOCAL_DB_PATH"; then
  rm -f "$LOCAL_SNAPSHOT_PATH"
  echo "==> 主备数据库内容一致，跳过替换与重启"
  echo "✅ 主库同步完成：无需更新"
  exit 0
fi

if [ -f "$LOCAL_DB_PATH" ]; then
  cp "$LOCAL_DB_PATH" "${LOCAL_DB_PATH}.before-sync.bak"
fi
mv "$LOCAL_SNAPSHOT_PATH" "$LOCAL_DB_PATH"
rm -f "${LOCAL_DB_PATH}-wal" "${LOCAL_DB_PATH}-shm"

echo "==> [4/4] 重启本地备站服务"
"$SCRIPT_DIR/restart-health-server.sh"

echo "✅ 主库同步完成：$PRIMARY_HOST -> $LOCAL_DB_PATH"
