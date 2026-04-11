#!/usr/bin/env bash

BRUH_LOADED_ENV_FILES=()

normalize_bruh_app_env() {
  local value="${1:-}"
  local normalized
  normalized="$(printf '%s' "$value" | tr '[:upper:]' '[:lower:]')"

  case "$normalized" in
    dev|development|local|debug)
      echo "dev"
      ;;
    staging|stage|stg|qa|test)
      echo "staging"
      ;;
    prod|production|release|live|"")
      echo "prod"
      ;;
    *)
      echo "$normalized"
      ;;
  esac
}

_bruh_source_env_file() {
  local path="$1"
  [[ -f "$path" ]] || return 1

  local had_allexport=0
  if [[ -o allexport ]]; then
    had_allexport=1
  else
    set -a
  fi

  # shellcheck disable=SC1090
  . "$path"

  if [[ "$had_allexport" -eq 0 ]]; then
    set +a
  fi

  BRUH_LOADED_ENV_FILES+=("${path##*/}")
  return 0
}

load_bruh_env() {
  local root_dir="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
  local requested_env="${2:-${BRUH_APP_ENV:-}}"

  BRUH_LOADED_ENV_FILES=()

  _bruh_source_env_file "$root_dir/.env" || true
  _bruh_source_env_file "$root_dir/.env.local" || true

  local resolved_env
  resolved_env="$(normalize_bruh_app_env "${requested_env:-${BRUH_APP_ENV:-prod}}")"
  export BRUH_APP_ENV="$resolved_env"

  _bruh_source_env_file "$root_dir/.env.$resolved_env" || true
  _bruh_source_env_file "$root_dir/.env.$resolved_env.local" || true
}
