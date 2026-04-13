#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
LOG_DIR="$PROJECT_DIR/logs"
PID_FILE="$LOG_DIR/server.pid"

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

is_health_server_process() {
  local pid="$1"
  ps -o command= -p "$pid" 2>/dev/null | grep -Eq "(\.next/standalone/server\.js|(^|[[:space:]])server\.js([[:space:]]|$)|next-server)"
}

stop_pid() {
  local pid="$1"
  [ -n "$pid" ] || return 1
  if ! kill -0 "$pid" 2>/dev/null; then
    return 1
  fi

  if ! is_health_server_process "$pid"; then
    return 1
  fi

  kill "$pid" 2>/dev/null || true
  for _ in {1..20}; do
    if ! kill -0 "$pid" 2>/dev/null; then
      return 0
    fi
    sleep 0.5
  done

  kill -9 "$pid" 2>/dev/null || true
  return 0
}

STOPPED=0

if [ -f "$PID_FILE" ]; then
  PID_FROM_FILE="$(cat "$PID_FILE" 2>/dev/null || true)"
  if stop_pid "${PID_FROM_FILE:-}"; then
    STOPPED=1
  fi
  rm -f "$PID_FILE"
fi

LISTENERS="$(lsof -tiTCP:"$PORT" -sTCP:LISTEN 2>/dev/null || true)"
if [ -n "$LISTENERS" ]; then
  while IFS= read -r pid; do
    [ -n "$pid" ] || continue
    if stop_pid "$pid"; then
      STOPPED=1
    fi
  done <<< "$LISTENERS"
fi

if [ "$STOPPED" -eq 1 ]; then
  echo "Health server stopped"
else
  echo "Health server was not running"
fi
