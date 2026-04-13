#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

resolve_entrypoint() {
  if [ -f ".next/standalone/server.js" ]; then
    echo ".next/standalone/server.js"
    return 0
  fi

  if [ -f "server.js" ]; then
    echo "server.js"
    return 0
  fi

  return 1
}

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

export PATH="/opt/homebrew/opt/node@22/bin:/opt/homebrew/bin:$HOME/local/bin:$PATH"
export NODE_ENV="${NODE_ENV:-production}"
export PORT="${PORT:-3000}"
export HOSTNAME="${HOSTNAME:-0.0.0.0}"

cd "$PROJECT_DIR"

if [ -f "$ENV_FILE" ]; then
  set -a
  # shellcheck disable=SC1090
  source "$ENV_FILE"
  set +a
fi

ENTRYPOINT="$(resolve_entrypoint || true)"

if [ -z "$ENTRYPOINT" ] && [ -f "package.json" ]; then
  echo "Missing standalone bundle, running build first..."
  npm run build
  ENTRYPOINT="$(resolve_entrypoint || true)"
fi

if [ -z "$ENTRYPOINT" ]; then
  echo "Could not find a runnable server entrypoint (server.js or .next/standalone/server.js)." >&2
  exit 1
fi

exec node "$ENTRYPOINT"
