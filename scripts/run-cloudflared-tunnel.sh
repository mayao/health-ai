#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ENV_FILE=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --env-file)
      ENV_FILE="${2:-}"
      if [ -z "$ENV_FILE" ]; then
        echo "--env-file requires a path" >&2
        exit 1
      fi
      shift 2
      ;;
    *)
      echo "Unknown argument: $1" >&2
      echo "Usage: $0 [--env-file /path/to/cloudflared.env]" >&2
      exit 1
      ;;
  esac
done

if [ -n "$ENV_FILE" ]; then
  if [ ! -f "$ENV_FILE" ]; then
    echo "Cloudflared env file not found: $ENV_FILE" >&2
    exit 1
  fi

  set -a
  # shellcheck disable=SC1090
  source "$ENV_FILE"
  set +a
fi

if [ -z "${TUNNEL_TOKEN:-}" ]; then
  echo "TUNNEL_TOKEN is required to run cloudflared." >&2
  exit 1
fi

find_cloudflared_bin() {
  local candidate=""

  if [ -n "${CLOUDFLARED_BIN:-}" ]; then
    candidate="$CLOUDFLARED_BIN"
    [ -x "$candidate" ] && echo "$candidate" && return 0
    echo "Configured CLOUDFLARED_BIN is not executable: $candidate" >&2
    return 1
  fi

  if command -v cloudflared >/dev/null 2>&1; then
    command -v cloudflared
    return 0
  fi

  for candidate in /opt/homebrew/bin/cloudflared /usr/local/bin/cloudflared "$HOME/local/bin/cloudflared"; do
    if [ -x "$candidate" ]; then
      echo "$candidate"
      return 0
    fi
  done

  return 1
}

CLOUDFLARED_BIN="$(find_cloudflared_bin || true)"
if [ -z "$CLOUDFLARED_BIN" ]; then
  echo "cloudflared binary not found. Install it first or set CLOUDFLARED_BIN in the env file." >&2
  exit 1
fi

mkdir -p "$PROJECT_DIR/logs"

ARGS=(tunnel --no-autoupdate)
if [ -n "${TUNNEL_LOG_LEVEL:-}" ]; then
  ARGS+=(--loglevel "$TUNNEL_LOG_LEVEL")
fi
if [ -n "${TUNNEL_METRICS:-}" ]; then
  ARGS+=(--metrics "$TUNNEL_METRICS")
fi
if [ -n "${TUNNEL_TRANSPORT_PROTOCOL:-}" ]; then
  ARGS+=(--protocol "$TUNNEL_TRANSPORT_PROTOCOL")
fi
ARGS+=(run --token "$TUNNEL_TOKEN")

exec "$CLOUDFLARED_BIN" "${ARGS[@]}"
