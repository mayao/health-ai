#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PLIST_PATH="$HOME/Library/LaunchAgents/com.healthai.backup-db-sync.plist"
SYNC_SCRIPT="$PROJECT_DIR/scripts/sync-primary-db-to-backup.sh"
INTERVAL_SECONDS="${INTERVAL_SECONDS:-600}"

if [ ! -x "$SYNC_SCRIPT" ]; then
  echo "❌ 同步脚本不存在或不可执行: $SYNC_SCRIPT" >&2
  exit 1
fi

mkdir -p "$HOME/Library/LaunchAgents"
mkdir -p "$PROJECT_DIR/logs"

cat > "$PLIST_PATH" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>com.healthai.backup-db-sync</string>
  <key>ProgramArguments</key>
  <array>
    <string>$SYNC_SCRIPT</string>
  </array>
  <key>WorkingDirectory</key>
  <string>$PROJECT_DIR</string>
  <key>StartInterval</key>
  <integer>$INTERVAL_SECONDS</integer>
  <key>RunAtLoad</key>
  <true/>
  <key>StandardOutPath</key>
  <string>$PROJECT_DIR/logs/com.healthai.backup-db-sync.log</string>
  <key>StandardErrorPath</key>
  <string>$PROJECT_DIR/logs/com.healthai.backup-db-sync.error.log</string>
</dict>
</plist>
EOF

launchctl bootout "gui/$(id -u)/com.healthai.backup-db-sync" >/dev/null 2>&1 || true
launchctl bootstrap "gui/$(id -u)" "$PLIST_PATH"
launchctl kickstart -k "gui/$(id -u)/com.healthai.backup-db-sync"

echo "✅ 已安装备站数据库定时同步任务: com.healthai.backup-db-sync"
echo "   间隔: ${INTERVAL_SECONDS}s"
echo "   日志: $PROJECT_DIR/logs/com.healthai.backup-db-sync.log"
