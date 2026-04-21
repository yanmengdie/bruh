#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
RUNTIME_ENV_FILE="${BRUH_RUNTIME_ENV_FILE:-/opt/bruh-selfhost/runtime/.env}"

if [[ -f "$RUNTIME_ENV_FILE" ]]; then
  set -a
  # shellcheck disable=SC1090
  . "$RUNTIME_ENV_FILE"
  set +a
fi

cd "$ROOT_DIR"

# shellcheck source=/dev/null
source "$ROOT_DIR/scripts/load_env.sh"
load_bruh_env "$ROOT_DIR" "${BRUH_APP_ENV:-prod}"

echo "==> Weibo ingest environment: ${BRUH_APP_ENV}"
if [[ ${#BRUH_LOADED_ENV_FILES[@]} -gt 0 ]]; then
  echo "==> Loaded env files: ${BRUH_LOADED_ENV_FILES[*]}"
else
  echo "==> Loaded env files: none"
fi

exec python3 "$ROOT_DIR/scripts/ingest_weibo.py"
