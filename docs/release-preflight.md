# Release Preflight

## Goal

Provide one operator-facing command that checks release readiness without changing the user interface.

## Commands

Backend-only preflight:

```bash
deno run --allow-env --allow-net scripts/release_preflight.ts --strict
```

Full release preflight:

```bash
./scripts/run_release_preflight.sh
```

The shell wrapper auto-loads `.env`, `.env.local`, `.env.<env>`, and `.env.<env>.local`, then runs the backend preflight first and finally executes `scripts/run_p1_validation.sh`.

## What Gets Checked

Environment variables:

- required: `PROJECT_URL` / `SUPABASE_URL`
- required: `SERVICE_ROLE_KEY` / `SUPABASE_SERVICE_ROLE_KEY`
- required: `BRUH_FUNCTIONS_BASE_URL` / `SUPABASE_FUNCTIONS_BASE_URL`
- required: `BRUH_SUPABASE_ANON_KEY` / `SUPABASE_ANON_KEY`
- recommended: `OPENAI_API_KEY` or `ANTHROPIC_API_KEY`
- recommended: `NANO_BANANA_API_KEY`
- recommended: `VOICE_API_KEY`
- recommended: `APIFY_TOKEN`

Critical backend tables:

- `pipeline_job_locks`
- `news_articles`
- `news_events`
- `persona_news_scores`
- `feed_items`
- `source_posts`

Validation gates:

- backend health must be `healthy` or `running`
- required environment variables must resolve for the active `BRUH_APP_ENV`
- critical tables must be queryable with service-role credentials
- local contract/smoke validation must pass through `scripts/run_p1_validation.sh`

## Suggested Runbook

1. Export the target environment, for example `BRUH_APP_ENV=staging` or `BRUH_APP_ENV=prod`.
2. Copy `scripts/preflight.env.template` into an ignored local file such as `.env.staging.local` or `.env.prod.local`, then fill in real values.
3. Confirm the target environment has scoped keys such as `PROJECT_URL__STAGING` and `SERVICE_ROLE_KEY__STAGING`, or provide the equivalent values in the matching local `.env.<env>.local` file.
4. Run `./scripts/run_release_preflight.sh`.
5. If the backend preflight fails, fix missing env vars, broken table access, or stale backend health before release.
6. If local validation fails, fix contract drift, content graph regressions, or backend test failures before release.

## Notes

- Optional provider keys show up as warnings, not hard failures.
- Missing required environment variables or unhealthy backend state will fail `--strict`.
- The preflight is intentionally read-only for backend data. It does not claim job locks or mutate tables.
- The wrapper prints which ignored env files were loaded so operators can debug the active configuration quickly.
