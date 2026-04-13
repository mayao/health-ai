#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
LOG_DIR="$PROJECT_DIR/logs"
PID_FILE="$LOG_DIR/server.pid"
RUN_SCRIPT="$SCRIPT_DIR/run-health-server.sh"
STDOUT_LOG="$LOG_DIR/server.log"
STDERR_LOG="$LOG_DIR/server.error.log"

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

mkdir -p "$LOG_DIR"

is_health_server_process() {
  local pid="$1"
  ps -o command= -p "$pid" 2>/dev/null | grep -Eq "(\.next/standalone/server\.js|(^|[[:space:]])server\.js([[:space:]]|$)|next-server)"
}

cleanup_pid_file() {
  if [ -f "$PID_FILE" ]; then
    local existing_pid
    existing_pid="$(cat "$PID_FILE" 2>/dev/null || true)"
    if [ -n "${existing_pid:-}" ] && kill -0 "$existing_pid" 2>/dev/null; then
      if is_health_server_process "$existing_pid"; then
        echo "Health server is already running on pid $existing_pid"
        exit 0
      fi
    fi
    rm -f "$PID_FILE"
  fi
}

ensure_port_available() {
  local listeners
  listeners="$(lsof -tiTCP:"$PORT" -sTCP:LISTEN 2>/dev/null || true)"
  [ -n "$listeners" ] || return 0

  while IFS= read -r pid; do
    [ -n "$pid" ] || continue
    if is_health_server_process "$pid"; then
      echo "Port $PORT is already occupied by the health server (pid $pid)"
      echo "$pid" > "$PID_FILE"
      exit 0
    fi
    echo "Port $PORT is occupied by another process (pid $pid). Please free the port first."
    exit 1
  done <<< "$listeners"
}

rotate_log() {
  local file="$1"
  if [ -f "$file" ]; then
    mv "$file" "${file%.log}.previous.log"
  fi
  : > "$file"
}

cleanup_pid_file
ensure_port_available
rotate_log "$STDOUT_LOG"
rotate_log "$STDERR_LOG"

nohup "$RUN_SCRIPT" >> "$STDOUT_LOG" 2>> "$STDERR_LOG" &
SERVER_PID=$!
echo "$SERVER_PID" > "$PID_FILE"

sleep 2
if kill -0 "$SERVER_PID" 2>/dev/null; then
  echo "Health server started on pid $SERVER_PID"
else
  echo "Health server failed to start. Check $STDERR_LOG"
  rm -f "$PID_FILE"
  exit 1
fi
