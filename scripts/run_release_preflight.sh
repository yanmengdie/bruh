#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
export PATH="/opt/homebrew/bin:$PATH"

cd "$ROOT_DIR"

echo "==> Backend release preflight"
deno run --allow-env --allow-net scripts/release_preflight.ts --strict

echo "==> Local validation"
./scripts/run_p1_validation.sh

echo "Release preflight passed"
