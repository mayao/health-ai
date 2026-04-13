#!/bin/bash
set -euo pipefail

ENV_FILE="${1:-}"
if [ -z "$ENV_FILE" ]; then
  echo "Usage: $0 /absolute/path/to/cloudflared-backup.env" >&2
  exit 1
fi

if [ ! -f "$ENV_FILE" ]; then
  echo "Cloudflared env file not found: $ENV_FILE" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
RUN_SCRIPT="${PROJECT_DIR}/scripts/run-cloudflared-tunnel.sh"
LABEL="${LABEL:-com.healthai.cloudflared-backup}"
PLIST_PATH="$HOME/Library/LaunchAgents/${LABEL}.plist"

if [ ! -x "$RUN_SCRIPT" ]; then
  echo "Cloudflared run script not found or not executable: $RUN_SCRIPT" >&2
  exit 1
fi

mkdir -p "$HOME/Library/LaunchAgents" "$PROJECT_DIR/logs"

cat > "$PLIST_PATH" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
  <dict>
    <key>Label</key>
    <string>${LABEL}</string>
    <key>ProgramArguments</key>
    <array>
      <string>${RUN_SCRIPT}</string>
      <string>--env-file</string>
      <string>${ENV_FILE}</string>
    </array>
    <key>KeepAlive</key>
    <true/>
    <key>RunAtLoad</key>
    <true/>
    <key>WorkingDirectory</key>
    <string>${PROJECT_DIR}</string>
    <key>StandardOutPath</key>
    <string>${PROJECT_DIR}/logs/${LABEL}.log</string>
    <key>StandardErrorPath</key>
    <string>${PROJECT_DIR}/logs/${LABEL}.error.log</string>
  </dict>
</plist>
EOF

launchctl bootout "gui/$(id -u)" "$PLIST_PATH" >/dev/null 2>&1 || true
launchctl bootstrap "gui/$(id -u)" "$PLIST_PATH"
launchctl kickstart -k "gui/$(id -u)/${LABEL}"

echo "Installed launchd agent: ${LABEL}"
echo "plist: ${PLIST_PATH}"
