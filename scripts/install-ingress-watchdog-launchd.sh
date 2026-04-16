#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
RUN_SCRIPT="${PROJECT_DIR}/scripts/ensure-public-ingress-healthy.sh"
LABEL="${LABEL:-com.healthai.ingress-watchdog}"
PLIST_PATH="$HOME/Library/LaunchAgents/${LABEL}.plist"
START_INTERVAL="${START_INTERVAL:-60}"

if [ ! -x "$RUN_SCRIPT" ]; then
  echo "Ingress watchdog script not found or not executable: $RUN_SCRIPT" >&2
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
    <key>RunAtLoad</key>
    <true/>
    <key>StartInterval</key>
    <integer>${START_INTERVAL}</integer>
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
