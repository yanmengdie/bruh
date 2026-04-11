#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

client_paths=(
  "bruh"
  "bruh.xcodeproj/project.pbxproj"
)

forbidden_pattern='(SERVICE_ROLE_KEY|SUPABASE_SERVICE_ROLE_KEY|OPENAI_API_KEY|ANTHROPIC_API_KEY|VOICE_API_KEY|APIFY_TOKEN|NANO_BANANA_API_KEY|TWITTER_AUTH_TOKEN|TWITTER_CT0)'

if matches="$(rg -n --color=never -e "$forbidden_pattern" "${client_paths[@]}" || true)"; [[ -n "$matches" ]]; then
  printf 'Client boundary violation: server-only secret references found in iOS app surface:\n%s\n' "$matches" >&2
  exit 1
fi

echo "Client boundary scan passed"
