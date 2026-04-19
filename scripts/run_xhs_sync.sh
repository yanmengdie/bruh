#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
XHS_DIR="$ROOT_DIR/tools/xhs"
AUTH_DIR="$XHS_DIR/.auth"
RUNTIME_ENV_FILE="${BRUH_RUNTIME_ENV_FILE:-/opt/bruh-selfhost/runtime/.env}"
STORAGE_STATE_FILE="${XHS_STORAGE_STATE_FILE:-${BRUH_XHS_STORAGE_STATE_FILE:-/opt/bruh-selfhost/runtime/xhs-storage-state.json}}"

if [[ -f "$RUNTIME_ENV_FILE" ]]; then
  set -a
  # shellcheck disable=SC1090
  . "$RUNTIME_ENV_FILE"
  set +a
fi

QUERY="${BRUH_XHS_SYNC_QUERY:-影石刘靖康}"
PERSONA_ID="${BRUH_XHS_SYNC_PERSONA_ID:-影石刘靖康}"
LIMIT="${BRUH_XHS_SYNC_LIMIT:-5}"
FUNCTIONS_URL="${SUPABASE_FUNCTIONS_URL:-${BRUH_FUNCTIONS_BASE_URL:-http://127.0.0.1:17322/functions/v1}}"
ANON_KEY="${SUPABASE_ANON_KEY:-${BRUH_SUPABASE_ANON_KEY:-}}"
COOKIE_STRING="${XHS_COOKIE:-}"

if [[ ! -d "$XHS_DIR" ]]; then
  echo "Missing tools/xhs directory at $XHS_DIR" >&2
  exit 1
fi

if [[ ! -f "$STORAGE_STATE_FILE" && -z "$COOKIE_STRING" && ! -d "$AUTH_DIR" ]]; then
  echo "Missing usable XHS auth. Expected one of: $STORAGE_STATE_FILE, XHS_COOKIE, or $AUTH_DIR" >&2
  exit 1
fi

if [[ -z "$ANON_KEY" ]]; then
  echo "Missing SUPABASE_ANON_KEY / BRUH_SUPABASE_ANON_KEY for XHS sync" >&2
  exit 1
fi

cd "$XHS_DIR"

XHS_STORAGE_STATE_FILE="$STORAGE_STATE_FILE" \
XHS_COOKIE="$COOKIE_STRING" \
SUPABASE_FUNCTIONS_URL="$FUNCTIONS_URL" \
SUPABASE_ANON_KEY="$ANON_KEY" \
node sync-profile.mjs \
  --query "$QUERY" \
  --limit "$LIMIT" \
  --persona-id "$PERSONA_ID" \
  --ingest \
  --build-feed false
