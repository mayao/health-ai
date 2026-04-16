#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
LOG_DIR="$PROJECT_DIR/logs"
WATCHDOG_LOG="$LOG_DIR/watchdog.log"

mkdir -p "$LOG_DIR"
touch "$WATCHDOG_LOG"

BEGIN_MARKER="# HEALTH_SERVER_WATCHDOG_BEGIN"
END_MARKER="# HEALTH_SERVER_WATCHDOG_END"

BOOT_LINE="@reboot cd \"$PROJECT_DIR\" && \"$SCRIPT_DIR/start-health-server.sh\" >> \"$WATCHDOG_LOG\" 2>&1"
CHECK_LINE="* * * * * cd \"$PROJECT_DIR\" && \"$SCRIPT_DIR/ensure-health-server.sh\" >> \"$WATCHDOG_LOG\" 2>&1"
INGRESS_CHECK_LINE="* * * * * cd \"$PROJECT_DIR\" && \"$SCRIPT_DIR/ensure-public-ingress-healthy.sh\" >> \"$WATCHDOG_LOG\" 2>&1"

CURRENT_CRON="$(crontab -l 2>/dev/null || true)"

FILTERED_CRON="$(printf "%s\n" "$CURRENT_CRON" | awk '
  /# HEALTH_SERVER_WATCHDOG_BEGIN/ {skip=1; next}
  /# HEALTH_SERVER_WATCHDOG_END/ {skip=0; next}
  !skip {print}
')"

{
  printf "%s\n" "$FILTERED_CRON"
  echo "$BEGIN_MARKER"
  echo "$BOOT_LINE"
  echo "$CHECK_LINE"
  echo "$INGRESS_CHECK_LINE"
  echo "$END_MARKER"
} | sed '/^[[:space:]]*$/N;/^\n$/D' | crontab -

echo "Watchdog cron installed for user $(whoami)."
echo "Entries:"
crontab -l | awk "/$BEGIN_MARKER/,/$END_MARKER/"

# Run once right away to ensure service is healthy.
"$SCRIPT_DIR/ensure-health-server.sh" || true
