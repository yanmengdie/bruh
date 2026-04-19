# Self-Hosted Backend Cutover

## Goal

Document what has already been moved off hosted Supabase, what still uses compatibility naming only, and what must be true before the hosted project can be deleted safely.

## Current Status

The backend data plane is already self-hosted.

Current server:

- SSH target: `root@210.73.43.5:17322`
- Hostname: `ubuntu22`

Current self-hosted runtime:

- PostgreSQL 16 stores the app data locally.
- PostgREST serves the database through a Supabase-compatible REST layer.
- A small local gateway strips `/rest/v1` so existing `supabase-js createClient(projectUrl, key)` calls continue to work.
- A functions gateway exposes `/functions/v1/*`.
- Each function runs as an individual systemd service.
- Scheduled jobs now run from server cron instead of Supabase `pg_cron` / `pg_net`.

## What Has Been Migrated

### Database

- `public` schema and data snapshot have been imported into local PostgreSQL.
- Core row counts were verified after import:
  - `personas=14`
  - `persona_accounts=9`
  - `source_posts=166`
  - `feed_items=166`
  - `feed_comments=104`
  - `feed_likes=79`
  - `news_articles=616`
  - `news_events=590`
  - `news_event_articles=591`
  - `persona_news_scores=6960`

### App-Facing Functions

- `feed`
- `generate-message`
- `message-starters`
- `generate-post-interactions`

These are already reachable through the self-hosted functions gateway.

### Pipeline Functions

- `build-feed`
- `build-news-events`
- `ingest-top-news`
- `ingest-x-posts`
- `ingest-xhs-posts`

These are also running on the self-hosted server.

### Scheduling

- Supabase cron jobs have been replaced by `/etc/cron.d/bruh-selfhost`.
- The server now invokes functions locally through a wrapper script instead of calling hosted Supabase URLs.

## What Still Says “Supabase” But Is No Longer Hosted Supabase

The repo intentionally keeps a compatibility layer to avoid unnecessary code churn:

- `supabase/functions/...` directory naming stays unchanged.
- backend code still uses `supabase-js`.
- env names such as `PROJECT_URL`, `SUPABASE_URL`, `SERVICE_ROLE_KEY`, `SUPABASE_SERVICE_ROLE_KEY`, `BRUH_SUPABASE_ANON_KEY` remain supported.

In self-host mode these values point to the local compatibility layer, not to hosted Supabase.

## What This Project Does Not Use

From the current repo and config:

- no Supabase Auth dependency
- no Supabase Storage dependency
- no Supabase Realtime dependency

That means the meaningful hosted-Supabase migration surface for this project was:

- database
- functions
- cron
- secrets

The first three are already moved.

## Remaining Risks Before Deleting Hosted Supabase

### 1. Public ingress is still temporary

Current public functions URL:

- `https://frequencies-main-saver-eggs.trycloudflare.com/functions/v1`

This is a Cloudflare Quick Tunnel URL. It works for temporary validation, but it is not a stable production/TestFlight endpoint because the URL can change after tunnel restart or host restart.

### 2. Some secrets cannot be recovered from Supabase digests

Hosted Supabase only exposes secret digests, not plaintext values.

Already restored:

- OpenAI-compatible provider config

Still needs plaintext from the operator if those features are required:

- `APIFY_TOKEN`
- `VOICE_*`
- `NANO_BANANA_*`

### 3. One news source is blocked by server outbound connectivity

`ingest-top-news` is now self-hosted, but the server still times out when fetching BBC RSS over HTTPS. This is an outbound connectivity issue to the source, not a remaining Supabase dependency.

## Deletion Checklist

Before deleting the hosted Supabase project:

1. Replace the Quick Tunnel with a stable public endpoint.
2. Put the stable endpoint into app/tool env config and rerun preflight.
3. Run `./scripts/run_release_preflight.sh` against the self-hosted env.
4. Run `./scripts/run_backend_health_snapshot.sh --strict` against the self-hosted env.
5. Provide any still-needed third-party plaintext secrets to the server.
6. Keep one final SQL/data backup outside the hosted Supabase project.

## Server-Side Runtime References

Useful paths on the self-hosted server:

- runtime env: `/opt/bruh-selfhost/runtime/.env`
- Postgres env: `/opt/bruh-selfhost/runtime/postgres.env`
- PostgREST config: `/opt/bruh-selfhost/runtime/postgrest.conf`
- REST gateway: `/opt/bruh-selfhost/runtime/supabase_rest_gateway.ts`
- functions gateway: `/opt/bruh-selfhost/runtime/gateway.ts`
- cron invoke wrapper: `/opt/bruh-selfhost/runtime/invoke_function.sh`
- cron definition: `/etc/cron.d/bruh-selfhost`

## Practical Conclusion

For this repository, the hosted Supabase project is no longer the active backend runtime.

The remaining blockers to deletion are operational, not architectural:

- stable public ingress
- any missing third-party plaintext secrets
- final preflight/health verification against the self-hosted environment
