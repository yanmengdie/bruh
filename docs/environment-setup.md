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

## Backend Functions

The repo keeps `supabase/functions` and `supabase-js` naming for compatibility, but the active backend can be either hosted Supabase or a self-hosted PostgREST-compatible gateway.

Backend functions resolve `BRUH_APP_ENV` from environment variables and then apply the same scoped lookup.

Shared backend keys:

- `PROJECT_URL`
- `SERVICE_ROLE_KEY`

Aliases also supported:

- `SUPABASE_URL`
- `SUPABASE_SERVICE_ROLE_KEY`

Compatibility note:

- `PROJECT_URL` / `SUPABASE_URL` should point to a PostgREST-compatible REST endpoint.
- `SERVICE_ROLE_KEY` / `SUPABASE_SERVICE_ROLE_KEY` can be either a hosted Supabase service-role key or a self-hosted compatibility JWT.
- `BRUH_FUNCTIONS_BASE_URL` should point to the public functions gateway, usually ending with `/functions/v1`.
- `BRUH_SUPABASE_ANON_KEY` remains the client-side compatibility key name even when the backend is fully self-hosted.

Provider keys can also be scoped:

- `OPENAI_API_KEY`
- `OPENAI_BASE_URL`
- `OPENAI_MODEL`
- `NANO_BANANA_API_KEY`
- `NANO_BANANA_BASE_URL`
- `NANO_BANANA_MODEL`
- `VOICE_API_KEY`
- `VOICE_API_BASE_URL`
- `TWITTER_AUTH_TOKEN`
- `TWITTER_CT0`
- `TWITTER_BIN`

X ingestion provider keys can also be scoped:

- `BRUH_X_INGEST_PROVIDER`
- `BRUH_X_SELF_HOSTED_SERVICE_URL`
- `BRUH_X_SELF_HOSTED_SERVICE_TOKEN`
- `BRUH_X_SELF_HOSTED_SERVICE_TIMEOUT_MS`

Supported `BRUH_X_INGEST_PROVIDER` values:

- `self_hosted_service`

Provider-specific notes:

- `TWITTER_AUTH_TOKEN` / `TWITTER_CT0` are only required when `BRUH_X_INGEST_PROVIDER=self_hosted_service` and the crawler implementation uses `twitter-cli`.
- `BRUH_X_INGEST_PROVIDER=apify` is no longer supported by the function and will fail at runtime.
- `BRUH_X_INGEST_MODE` must still be `enabled` or the function will skip before calling either provider.

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

Operator shell wrappers now auto-load ignored local env files in this order:

- `.env`
- `.env.local`
- `.env.<env>`
- `.env.<env>.local`

Supported wrappers:

- `scripts/run_backend_health_snapshot.sh`
- `scripts/run_release_preflight.sh`

Required for ingestion and backend health checks:

- `SUPABASE_URL` or `PROJECT_URL`
- `SUPABASE_SERVICE_ROLE_KEY` or `SERVICE_ROLE_KEY`

Optional:

- `TWITTER_AUTH_TOKEN`
- `TWITTER_CT0`
- `HTTP_PROXY`
- `HTTPS_PROXY`
- `TWITTER_BIN`
- `BRUH_X_INGEST_PROVIDER`
- `BRUH_X_SELF_HOSTED_SERVICE_URL`
- `BRUH_X_SELF_HOSTED_SERVICE_TOKEN`

Useful operational command:

```bash
export BRUH_APP_ENV=staging
./scripts/run_backend_health_snapshot.sh --strict
```

Release preflight:

```bash
export BRUH_APP_ENV=staging
./scripts/run_release_preflight.sh
```

Template for local operator env files:

```bash
cp scripts/preflight.env.template .env.staging.local
```

## Suggested Local Setup

Example self-hosted `dev` values:

```bash
export BRUH_APP_ENV=dev

export PROJECT_URL__DEV=http://127.0.0.1:3000
export SERVICE_ROLE_KEY__DEV=your-local-service-role-jwt
export BRUH_FUNCTIONS_BASE_URL__DEV=https://backend.example.com/functions/v1
export BRUH_SUPABASE_ANON_KEY__DEV=your-local-anon-jwt

export OPENAI_API_KEY__DEV=...
export OPENAI_MODEL__DEV=gpt-4.1-mini
export BRUH_X_INGEST_PROVIDER__DEV=self_hosted_service
export BRUH_X_SELF_HOSTED_SERVICE_URL__DEV=http://127.0.0.1:8789/fetch
export BRUH_X_SELF_HOSTED_SERVICE_TOKEN__DEV=replace-me
```

Example self-hosted `staging` values:

```bash
export BRUH_APP_ENV=staging

export PROJECT_URL__STAGING=https://rest.example.com
export SERVICE_ROLE_KEY__STAGING=your-staging-service-role-jwt
export BRUH_FUNCTIONS_BASE_URL__STAGING=https://api.example.com/functions/v1
export BRUH_SUPABASE_ANON_KEY__STAGING=your-staging-anon-jwt
```

Equivalent local file setup:

```bash
cp scripts/preflight.env.template .env.prod.local
```

Then replace the placeholder values in `.env.prod.local` with real secrets that stay ignored by Git.

Do not commit real secrets or real service-role keys into the repository.

See [self-hosted-backend.md](./self-hosted-backend.md) for the current cutover status, runtime topology, and the deletion checklist for the hosted Supabase project.
See [self-hosted-x-ingest.md](./self-hosted-x-ingest.md) for the self-hosted X crawler deployment flow that replaces Apify.
