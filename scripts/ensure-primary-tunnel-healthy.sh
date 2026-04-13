#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
LOG_DIR="$PROJECT_DIR/logs"
WATCHDOG_LOG="$LOG_DIR/primary-tunnel-guard.log"
LOCK_DIR="$LOG_DIR/primary-tunnel-guard.lock"
STATE_FILE="$LOG_DIR/primary-tunnel-guard.state"

PRIMARY_TUNNEL_LABEL="${PRIMARY_TUNNEL_LABEL:-com.healthai.cloudflared-primary}"
PRIMARY_TUNNEL_VPN_SERVICE="${PRIMARY_TUNNEL_VPN_SERVICE:-台湾 - 台北}"
PRIMARY_TUNNEL_HEALTHCHECK_URL="${PRIMARY_TUNNEL_HEALTHCHECK_URL:-http://127.0.0.1:3001/api/health}"
PRIMARY_TUNNEL_METRICS_URL="${PRIMARY_TUNNEL_METRICS_URL:-http://127.0.0.1:42101/metrics}"
PRIMARY_TUNNEL_UNHEALTHY_THRESHOLD="${PRIMARY_TUNNEL_UNHEALTHY_THRESHOLD:-3}"

mkdir -p "$LOG_DIR"

if ! mkdir "$LOCK_DIR" 2>/dev/null; then
  exit 0
fi
trap 'rmdir "$LOCK_DIR" >/dev/null 2>&1 || true' EXIT

log_line() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$WATCHDOG_LOG"
}

is_app_healthy() {
  local payload
  payload="$(curl -fsS --max-time 6 "$PRIMARY_TUNNEL_HEALTHCHECK_URL" 2>/dev/null || true)"
  [ -n "$payload" ] && echo "$payload" | grep -q '"status":"ok"'
}

active_connections() {
  local payload value
  payload="$(curl -fsS --max-time 4 "$PRIMARY_TUNNEL_METRICS_URL" 2>/dev/null || true)"
  if [ -z "$payload" ]; then
    echo -1
    return 0
  fi
  value="$(echo "$payload" | awk '/^cloudflared_tunnel_ha_connections / { print int($2); found = 1 } END { if (!found) print 0 }')"
  echo "${value:-0}"
}

vpn_is_connected() {
  scutil --nc status "$PRIMARY_TUNNEL_VPN_SERVICE" 2>/dev/null | head -n 1 | grep -q '^Connected'
}

current_primary_dns() {
  scutil --dns 2>/dev/null \
    | awk '
        /^resolver #1$/ { in_resolver = 1; next }
        in_resolver && /nameserver\[[0-9]+\] : / { print $3; count += 1; if (count >= 2) exit }
      ' \
    | paste -sd',' -
}

restart_primary_tunnel() {
  launchctl kickstart -k "gui/$(id -u)/${PRIMARY_TUNNEL_LABEL}" >/dev/null 2>&1 || true
}

wait_for_recovery() {
  local connections
  for _ in {1..15}; do
    sleep 2
    connections="$(active_connections)"
    if [ "${connections:-0}" -ge 1 ]; then
      echo "$connections"
      return 0
    fi
  done
  return 1
}

read_unhealthy_streak() {
  if [ -f "$STATE_FILE" ]; then
    cat "$STATE_FILE" 2>/dev/null || echo 0
  else
    echo 0
  fi
}

write_unhealthy_streak() {
  echo "$1" > "$STATE_FILE"
}

if ! is_app_healthy; then
  log_line "Skipped tunnel guard because app health check is failing at ${PRIMARY_TUNNEL_HEALTHCHECK_URL}."
  exit 0
fi

connections="$(active_connections)"
if [ "${connections:-0}" -ge 1 ]; then
  write_unhealthy_streak 0
  exit 0
fi

if [ "${connections:-0}" -lt 0 ]; then
  log_line "Skipped tunnel restart because metrics endpoint is temporarily unavailable: ${PRIMARY_TUNNEL_METRICS_URL}."
  exit 0
fi

unhealthy_streak="$(read_unhealthy_streak)"
if ! [[ "$unhealthy_streak" =~ ^[0-9]+$ ]]; then
  unhealthy_streak=0
fi
unhealthy_streak=$((unhealthy_streak + 1))
write_unhealthy_streak "$unhealthy_streak"

if [ "$unhealthy_streak" -lt "$PRIMARY_TUNNEL_UNHEALTHY_THRESHOLD" ]; then
  log_line "Primary tunnel reported zero connections (streak=${unhealthy_streak}/${PRIMARY_TUNNEL_UNHEALTHY_THRESHOLD}), waiting before restart."
  exit 0
fi

primary_dns="$(current_primary_dns)"
if vpn_is_connected; then
  log_line "Primary tunnel unhealthy (connections=${connections:-0}, dns=${primary_dns:-unknown}). Stopping VPN '${PRIMARY_TUNNEL_VPN_SERVICE}' to protect public ingress."
  scutil --nc stop "$PRIMARY_TUNNEL_VPN_SERVICE" >> "$WATCHDOG_LOG" 2>&1 || true
  sleep 5
else
  log_line "Primary tunnel unhealthy (connections=${connections:-0}, dns=${primary_dns:-unknown}). Restarting primary tunnel without VPN intervention."
fi

restart_primary_tunnel

if recovered="$(wait_for_recovery)"; then
  write_unhealthy_streak 0
  log_line "Primary tunnel recovered with ${recovered} active connections."
  exit 0
fi

log_line "Primary tunnel is still unhealthy after recovery attempt."
exit 1
