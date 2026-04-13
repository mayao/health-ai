#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
RUN_SCRIPT="$PROJECT_DIR/scripts/run-health-server.sh"
LABEL="${LABEL:-com.healthai.primary-app}"
PLIST_PATH="$HOME/Library/LaunchAgents/${LABEL}.plist"

if [ ! -x "$RUN_SCRIPT" ]; then
  echo "Health app run script not found or not executable: $RUN_SCRIPT" >&2
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

if launchctl bootout "gui/$(id -u)" "$PLIST_PATH" >/dev/null 2>&1 || true; then
  :
fi

if launchctl bootstrap "gui/$(id -u)" "$PLIST_PATH" >/dev/null 2>&1; then
  launchctl kickstart -k "gui/$(id -u)/${LABEL}"
  echo "Installed launchd agent: ${LABEL}"
  echo "plist: ${PLIST_PATH}"
  exit 0
fi

echo "launchd bootstrap failed, falling back to the existing background start script." >&2
"$PROJECT_DIR/scripts/start-health-server.sh"
