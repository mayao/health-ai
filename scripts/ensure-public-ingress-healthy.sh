#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
LOG_DIR="$PROJECT_DIR/logs"
WATCHDOG_LOG="$LOG_DIR/ingress-watchdog.log"
ALERT_LOG="$LOG_DIR/ingress-alert.log"
LOCK_DIR="$LOG_DIR/ingress-watchdog.lock"

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
TUNNEL_LABELS="${TUNNEL_LABELS:-com.healthai.cloudflared-primary com.healthai.cloudflared-backup}"
TUNNEL_METRICS_ENDPOINTS="${TUNNEL_METRICS_ENDPOINTS:-http://127.0.0.1:42101/metrics http://127.0.0.1:42102/metrics}"

mkdir -p "$LOG_DIR"

if ! mkdir "$LOCK_DIR" 2>/dev/null; then
  exit 0
fi
trap 'rmdir "$LOCK_DIR" >/dev/null 2>&1 || true' EXIT

log_line() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$WATCHDOG_LOG"
}

alert_line() {
  local message="[$(date '+%Y-%m-%d %H:%M:%S')] ALERT: $*"
  echo "$message" >> "$WATCHDOG_LOG"
  echo "$message" >> "$ALERT_LOG"
}

is_app_healthy() {
  local payload
  payload="$(curl -fsS --max-time 6 "$HEALTHCHECK_URL" 2>/dev/null || true)"
  [ -n "$payload" ] && echo "$payload" | grep -q '"status":"ok"'
}

ensure_backend() {
  if is_app_healthy; then
    return 0
  fi

  alert_line "Backend health check failed at ${HEALTHCHECK_URL}, restarting health server."
  if ! "$SCRIPT_DIR/restart-health-server.sh" >> "$WATCHDOG_LOG" 2>&1; then
    alert_line "Backend restart command failed."
    return 1
  fi

  for _ in {1..15}; do
    sleep 2
    if is_app_healthy; then
      log_line "Backend restart succeeded."
      return 0
    fi
  done

  alert_line "Backend restart attempted, but health check is still failing."
  return 1
}

metric_connections() {
  local endpoint="$1"
  local payload
  payload="$(curl -fsS --max-time 5 "$endpoint" 2>/dev/null || true)"
  if [ -z "$payload" ]; then
    echo -1
    return 0
  fi

  echo "$payload" | awk '/^cloudflared_tunnel_ha_connections / { print int($2); found = 1 } END { if (!found) print 0 }'
}

restart_tunnel_label() {
  local label="$1"
  local user_id
  user_id="$(id -u)"
  local restarted=0

  if launchctl kickstart -k "gui/${user_id}/${label}" >/dev/null 2>&1; then
    restarted=1
  fi
  if launchctl kickstart -k "user/${user_id}/${label}" >/dev/null 2>&1; then
    restarted=1
  fi
  if launchctl kickstart -k "system/${label}" >/dev/null 2>&1; then
    restarted=1
  fi

  if [ "$restarted" -eq 0 ]; then
    return 1
  fi

  return 0
}

check_tunnels() {
  local -a labels endpoints
  read -r -a labels <<< "$TUNNEL_LABELS"
  read -r -a endpoints <<< "$TUNNEL_METRICS_ENDPOINTS"

  local index=0
  local failed=0
  for endpoint in "${endpoints[@]}"; do
    local label=""
    if [ "$index" -lt "${#labels[@]}" ]; then
      label="${labels[$index]}"
    else
      label="cloudflared-$index"
    fi

    local connections
    connections="$(metric_connections "$endpoint")"
    if [ "$connections" -ge 1 ]; then
      index=$((index + 1))
      continue
    fi

    failed=1
    alert_line "Tunnel unhealthy: label=${label}, endpoint=${endpoint}, connections=${connections}. Restarting tunnel process."
    if restart_tunnel_label "$label"; then
      sleep 3
      local recovered
      recovered="$(metric_connections "$endpoint")"
      if [ "$recovered" -ge 1 ]; then
        log_line "Tunnel recovered: label=${label}, endpoint=${endpoint}, connections=${recovered}."
      else
        alert_line "Tunnel restart attempted but still unhealthy: label=${label}, endpoint=${endpoint}, connections=${recovered}."
      fi
    else
      alert_line "Unable to restart tunnel label ${label} automatically. Check launchctl permissions."
    fi

    index=$((index + 1))
  done

  return "$failed"
}

ensure_backend || exit 1
check_tunnels || exit 1
exit 0
