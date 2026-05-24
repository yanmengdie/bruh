#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/.build/p1"

mkdir -p "$BUILD_DIR"

cd "$ROOT_DIR"

./scripts/check_sensitive_strings.sh
./scripts/check_client_boundary.sh

bash -n \
  scripts/check_sensitive_strings.sh \
  scripts/check_client_boundary.sh \
  scripts/load_env.sh \
  scripts/run_p1_validation.sh

ENV_LOADER_SMOKE_DIR="$BUILD_DIR/env_loader_smoke"
rm -rf "$ENV_LOADER_SMOKE_DIR"
mkdir -p "$ENV_LOADER_SMOKE_DIR"
cp scripts/preflight.env.template "$ENV_LOADER_SMOKE_DIR/.env.prod.local"

bash -lc '
  set -euo pipefail
  root_dir="$1"
  env_dir="$2"
  source "$root_dir/scripts/load_env.sh"
  load_bruh_env "$env_dir" prod
  [[ "$BRUH_APP_ENV" == "prod" ]]
  [[ "$BRUH_FUNCTIONS_BASE_URL" == "http://8.141.119.22:3000/api" ]]
' bash "$ROOT_DIR" "$ENV_LOADER_SMOKE_DIR"

rm -rf "$ENV_LOADER_SMOKE_DIR"

swiftc \
  bruh/Services/AppEnvironment.swift \
  bruh/Networking/APIClientConfiguration.swift \
  bruh/Networking/RemoteMediaPolicy.swift \
  bruh/Networking/NetworkSupport.swift \
  bruh/Networking/APIContract.swift \
  bruh/Networking/NetworkRetryPolicy.swift \
  bruh/Networking/APIClientDTOs.swift \
  bruh/Networking/APIClientFeedDTOs.swift \
  bruh/Networking/APIClientMessageDTOs.swift \
  bruh/Networking/APIClientInteractionDTOs.swift \
  bruh/Networking/APIClient.swift \
  bruh/Networking/APIClientFeedEndpoints.swift \
  bruh/Networking/APIClientMessageEndpoints.swift \
  bruh/Networking/APIClientInteractionEndpoints.swift \
  scripts/api_contract_smoke.swift \
  -o "$BUILD_DIR/api_contract_smoke"
"$BUILD_DIR/api_contract_smoke"

swiftc \
  bruh/Models/PersonaPost.swift \
  bruh/Models/PersonaMessage.swift \
  bruh/Models/SourceItem.swift \
  bruh/Models/ContentGraphStore.swift \
  bruh/Models/ContentGraphStoreSupport.swift \
  bruh/Models/ContentGraphFeedSync.swift \
  bruh/Models/ContentGraphMessageSync.swift \
  scripts/content_graph_smoke.swift \
  -o "$BUILD_DIR/content_graph_smoke"
"$BUILD_DIR/content_graph_smoke"
