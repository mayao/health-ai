#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
LOG_DIR="$PROJECT_DIR/logs"
WATCHDOG_LOG="$LOG_DIR/watchdog.log"
LOCK_DIR="$LOG_DIR/watchdog.lock"

resolve_env_file() {
  if [ -n "${HEALTH_ENV_FILE:-}" ]; then
    case "$HEALTH_ENV_FILE" in
      /*) echo "$HEALTH_ENV_FILE" ;;
      *) echo "$PROJECT_DIR/$HEALTH_ENV_FILE" ;;
    esac
    return 0
  fi

  echo "$PROJECT_DIR/.env"
}

ENV_FILE="$(resolve_env_file)"
if [ -f "$ENV_FILE" ]; then
  set -a
  # shellcheck disable=SC1090
  source "$ENV_FILE"
  set +a
fi

PORT="${PORT:-3000}"
HEALTHCHECK_URL="${HEALTHCHECK_URL:-http://127.0.0.1:${PORT}/api/health}"

mkdir -p "$LOG_DIR"

# Prevent overlapping watchdog runs.
if ! mkdir "$LOCK_DIR" 2>/dev/null; then
  exit 0
fi
trap 'rmdir "$LOCK_DIR" >/dev/null 2>&1 || true' EXIT

log_line() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$WATCHDOG_LOG"
}

is_healthy() {
  local payload
  payload="$(curl -fsS --max-time 6 "$HEALTHCHECK_URL" 2>/dev/null || true)"
  [ -n "$payload" ] && echo "$payload" | grep -q '"status":"ok"'
}

if is_healthy; then
  exit 0
fi

log_line "Health check failed at $HEALTHCHECK_URL, restarting service."
if "$SCRIPT_DIR/restart-health-server.sh" >> "$WATCHDOG_LOG" 2>&1; then
  for _ in {1..10}; do
    sleep 2
    if is_healthy; then
      log_line "Restart succeeded."
      exit 0
    fi
  done
fi

log_line "Restart attempted, but health check is still failing."
exit 1
