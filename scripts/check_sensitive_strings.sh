#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

tracked_files=()
while IFS= read -r -d '' file; do
  [[ -e "$file" ]] || continue
  tracked_files+=("$file")
done < <(
  git ls-files -z -- \
    . \
    ':(exclude)docs/**' \
    ':(exclude)skills/**' \
    ':(exclude)output/**' \
    ':(exclude)Users/**'
)

if [[ ${#tracked_files[@]} -eq 0 ]]; then
  exit 0
fi

pattern='(sk-[A-Za-z0-9]{20,}|sbp_[A-Za-z0-9_-]{20,}|eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}|Authorization[[:space:]]*:[[:space:]]*["'"'"'"]?Bearer[[:space:]]+[A-Za-z0-9._-]{20,}|(SERVICE_ROLE_KEY|SUPABASE_SERVICE_ROLE_KEY|OPENAI_API_KEY|ANTHROPIC_API_KEY|APIFY_TOKEN|VOICE_API_KEY|TWITTER_AUTH_TOKEN|TWITTER_CT0|BRUH_X_SELF_HOSTED_SERVICE_TOKEN|X_INGEST_SERVICE_TOKEN|BRUH_X_SCRAPER_SERVICE_TOKEN)[[:space:]]*[:=][[:space:]]*["'"'"'"][^"'"'"']{12,}["'"'"'"])'

if matches="$(printf '%s\0' "${tracked_files[@]}" | xargs -0 rg -n --color=never -e "$pattern" || true)"; [[ -n "$matches" ]]; then
  printf 'Potential secret-like strings found:\n%s\n' "$matches" >&2
  exit 1
fi

echo "Sensitive string scan passed"
