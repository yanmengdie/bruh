# Observability

## Goal

Make backend request handling and pipeline jobs traceable without changing the user interface.

## Current Baseline

Shared helper:

- `supabase/functions/_shared/observability.ts`

Current capabilities:

- stable `requestId` generation per request/job
- `X-Bruh-Request-Id` response header for app-facing functions
- structured `request_started` / `request_succeeded` / `request_rejected` / `request_failed` events
- structured `job_started` / `job_skipped` / `job_succeeded` / `job_failed` events
- structured `provider_metric` events with `success` / `failure` / `fallback` / `skipped` outcomes
- automatic `durationMs` on completed request/job logs
- automatic `durationMs` on provider success/failure events
- normalized `errorCategory` classification for failure logs

## Current Coverage

App-facing functions:

- `feed`
- `generate-message`
- `message-starters`
- `generate-post-interactions`

Pipeline and ingestion functions:

- `build-feed`
- `build-news-events`
- `ingest-top-news`
- `ingest-x-posts`

Provider metric coverage:

- `generate-message` persona reply generation via `openai_compatible`
- `generate-message` message image generation via `nano_banana`
- `generate-message` voice reply generation via `tts_async`
- `message-starters` starter text generation via `openai_compatible`
- `message-starters` starter image generation via `nano_banana`
- `generate-post-interactions` interaction generation via `openai_compatible`
- `ingest-x-posts` X ingestion actor attempts and fallback chain across Apify actors

## Operational Usage

When a client request fails:

1. read `X-Bruh-Request-Id` from the response
2. search logs for that `requestId`
3. inspect the matching `request_started` and terminal event
4. use `durationMs`, `errorCategory`, and job/request details to locate the failing stage

When a cron or manual backend job misbehaves:

1. search by `scope`
2. check whether the last terminal event was `job_skipped`, `job_succeeded`, or `job_failed`
3. compare `durationMs` and counters such as `inserted`, `updated`, `normalized`, `eventCount`, or `feedItemCount`

When a provider starts degrading:

1. search logs for `event=provider_metric`
2. filter by `scope`, `operation`, and `provider`
3. compare `outcome`, `durationMs`, and `fallbackProvider`
4. correlate spikes in `failure` or `fallback` with the matching request/job `requestId`

## Health Snapshot Script

CLI:

- `scripts/backend_health_snapshot.ts`
- `scripts/run_backend_health_snapshot.sh`

Run manually:

```bash
./scripts/run_backend_health_snapshot.sh
```

Machine-readable output:

```bash
./scripts/run_backend_health_snapshot.sh --json
```

Fail the process when health is not `healthy` or `running`:

```bash
./scripts/run_backend_health_snapshot.sh --strict
```

What it checks:

- expected pipeline jobs in `pipeline_job_locks`
- freshness of `news_articles`, `news_events`, `persona_news_scores`, `feed_items`, `source_posts`
- most recent success / failure state
- row counts and recent-window counts

This is intentionally a read-only operator tool. It does not mutate job locks or trigger any function.

## Release Preflight

CLI:

- `scripts/release_preflight.ts`
- `scripts/run_release_preflight.sh`

Backend-only preflight:

```bash
deno run --allow-env --allow-net scripts/release_preflight.ts --strict
```

Full release gate:

```bash
./scripts/run_release_preflight.sh
```

What it checks:

- required and recommended environment variables for app and backend
- read access to critical tables such as `pipeline_job_locks`, `news_articles`, `news_events`, `persona_news_scores`, `feed_items`, `source_posts`
- backend freshness/health through `backend_health_snapshot`
- local contract and smoke validation through `run_p1_validation.sh`

See [release-preflight.md](./release-preflight.md) for the operator runbook.

Both shell wrappers auto-load ignored local env files and print the ones they actually used, which makes it easier to diagnose operator-side config drift without changing backend code.
