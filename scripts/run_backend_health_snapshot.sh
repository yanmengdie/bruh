#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
export PATH="/opt/homebrew/bin:$PATH"

cd "$ROOT_DIR"

# shellcheck source=/dev/null
source "$ROOT_DIR/scripts/load_env.sh"
load_bruh_env "$ROOT_DIR" "${BRUH_APP_ENV:-prod}"

echo "==> Backend health snapshot environment: ${BRUH_APP_ENV}"
if [[ ${#BRUH_LOADED_ENV_FILES[@]} -gt 0 ]]; then
  echo "==> Loaded env files: ${BRUH_LOADED_ENV_FILES[*]}"
else
  echo "==> Loaded env files: none"
fi

deno run --allow-env --allow-net scripts/backend_health_snapshot.ts "$@"
