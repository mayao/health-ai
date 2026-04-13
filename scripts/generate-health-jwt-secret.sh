#!/bin/bash
set -euo pipefail

if command -v openssl >/dev/null 2>&1; then
  openssl rand -base64 48 | tr -d '\n'
  echo
  exit 0
fi

node -e "console.log(require('node:crypto').randomBytes(48).toString('base64url'))"
