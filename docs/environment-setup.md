# Environment Setup

## Goal

The repo now supports explicit `dev`, `staging`, and `prod` configuration without changing UI code.

All runtime config follows the same rule:

- pick the current environment from `BRUH_APP_ENV`
- read `KEY__<ENV>` first
- fall back to `KEY`

Examples:

- `PROJECT_URL__DEV`
- `SERVICE_ROLE_KEY__STAGING`
- `BRUH_FUNCTIONS_BASE_URL__PROD`
- `OPENAI_MODEL__DEV`

Accepted environment names:

- `dev`, `development`, `local`, `debug`
- `staging`, `stage`, `stg`, `qa`, `test`
- `prod`, `production`, `release`, `live`

## iOS App

`bruh` resolves `BRUH_APP_ENV` from:

1. process environment
2. generated `Info.plist`
3. build default: `dev` for Debug, `prod` for Release

Supported app config keys:

- `BRUH_FUNCTIONS_BASE_URL`
- `SUPABASE_FUNCTIONS_BASE_URL`
- `BRUH_SUPABASE_ANON_KEY`
- `SUPABASE_ANON_KEY`
- all runtime flags already used by `AppRuntimeOptions`, such as `BRUH_ENABLE_LOCAL_STARTER_FALLBACKS`

Environment-scoped examples:

- `BRUH_FUNCTIONS_BASE_URL__DEV`
- `BRUH_FUNCTIONS_BASE_URL__STAGING`
- `BRUH_SUPABASE_ANON_KEY__PROD`
- `BRUH_ENABLE_LOCAL_STARTER_FALLBACKS__DEV`

Important:

- Debug builds default to `dev`
- Release builds default to `prod`
- local/demo fallback flags now default to `true` only for Debug + `dev`

## Supabase Edge Functions

Edge Functions resolve `BRUH_APP_ENV` from environment variables and then apply the same scoped lookup.

Shared Supabase keys:

- `PROJECT_URL`
- `SERVICE_ROLE_KEY`

Aliases also supported:

- `SUPABASE_URL`
- `SUPABASE_SERVICE_ROLE_KEY`

Provider keys can also be scoped:

- `OPENAI_API_KEY`
- `OPENAI_BASE_URL`
- `OPENAI_MODEL`
- `ANTHROPIC_API_KEY`
- `ANTHROPIC_BASE_URL`
- `ANTHROPIC_MODEL`
- `NANO_BANANA_API_KEY`
- `NANO_BANANA_BASE_URL`
- `NANO_BANANA_MODEL`
- `VOICE_API_KEY`
- `VOICE_API_BASE_URL`
- `APIFY_TOKEN`

Feature flags can also be scoped:

- `BRUH_ENABLED_PERSONA_IDS`
- `BRUH_STARTER_SELECTION_STRATEGY`
- `BRUH_STARTER_IMAGE_MODE`
- `BRUH_STARTER_SOURCE_URL_MODE`
- `BRUH_FEED_READ_SOURCE`
- `BRUH_FEED_RANKING_STRATEGY`

See [feature-flags.md](./feature-flags.md) for rollout semantics and examples.

Cost-control flags can also be scoped:

- `BRUH_LLM_GENERATION_MODE`
- `BRUH_TTS_MODE`
- `BRUH_TTS_MAX_CHARACTERS`
- `BRUH_MESSAGE_IMAGE_MODE`
- `BRUH_X_INGEST_MODE`
- `BRUH_X_INGEST_MAX_USERNAMES_PER_RUN`
- `BRUH_X_INGEST_MAX_POSTS_PER_USER`

See [cost-controls.md](./cost-controls.md) for degradation policy and rollout examples.

## Scripts

`scripts/ingest_x.py` now follows the same convention.

`scripts/backend_health_snapshot.ts` uses the same scoped environment rules through the shared backend environment layer.

Required for ingestion:

- `SUPABASE_URL` or `PROJECT_URL`
- `SUPABASE_SERVICE_ROLE_KEY` or `SERVICE_ROLE_KEY`

Optional:

- `TWITTER_AUTH_TOKEN`
- `TWITTER_CT0`
- `HTTP_PROXY`
- `HTTPS_PROXY`
- `TWITTER_BIN`

Useful operational command:

```bash
export BRUH_APP_ENV=staging
deno run --allow-env --allow-net scripts/backend_health_snapshot.ts --strict
```

Release preflight:

```bash
export BRUH_APP_ENV=staging
./scripts/run_release_preflight.sh
```

## Suggested Local Setup

Example `dev` values:

```bash
export BRUH_APP_ENV=dev

export PROJECT_URL__DEV=https://your-dev-project.supabase.co
export SERVICE_ROLE_KEY__DEV=...
export BRUH_FUNCTIONS_BASE_URL__DEV=https://your-dev-project.supabase.co/functions/v1
export BRUH_SUPABASE_ANON_KEY__DEV=...

export OPENAI_API_KEY__DEV=...
export OPENAI_MODEL__DEV=gpt-4.1-mini
```

Example `staging` values:

```bash
export BRUH_APP_ENV=staging

export PROJECT_URL__STAGING=https://your-staging-project.supabase.co
export SERVICE_ROLE_KEY__STAGING=...
export BRUH_FUNCTIONS_BASE_URL__STAGING=https://your-staging-project.supabase.co/functions/v1
export BRUH_SUPABASE_ANON_KEY__STAGING=...
```

Do not commit real secrets or real service-role keys into the repository.
