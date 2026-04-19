# Self-Hosted X Ingest

## Goal

Replace the current `Apify` dependency in `ingest-x-posts` with a self-hosted crawler running on the same server.

## Current Shape

The repo now supports two X ingest providers:

- `apify`
- `self_hosted_service`

Switch with:

```bash
export BRUH_X_INGEST_PROVIDER=self_hosted_service
```

## Architecture

The self-hosted mode keeps the existing ingest pipeline intact:

1. `scripts/x_scrape_service.py` fetches recent X posts.
2. The service returns normalized post payloads over HTTP.
3. `supabase/functions/ingest-x-posts/index.ts` calls that service.
4. `ingest-x-posts` still owns content-safety checks, dedupe, and `source_posts` upsert.
5. `build-feed` and the iOS app remain unchanged.

This is intentional. The crawler implementation can change later without changing the feed pipeline contract.

## Service Endpoints

Health check:

```bash
curl http://127.0.0.1:8789/health
```

Fetch request:

```bash
curl -X POST http://127.0.0.1:8789/fetch \
  -H 'Content-Type: application/json' \
  -H 'Authorization: Bearer <token>' \
  -d '{"usernames":["elonmusk","realdonaldtrump"],"limitPerUser":5}'
```

## Required Inputs

The default implementation uses a local `twitter` CLI and cookie/session style auth:

- `TWITTER_AUTH_TOKEN`
- `TWITTER_CT0`
- `TWITTER_BIN` if the binary is not simply `twitter`

Optional:

- `HTTP_PROXY`
- `HTTPS_PROXY`
- `BRUH_X_SELF_HOSTED_SERVICE_TOKEN`

## Local Runbook

Start the crawler service:

```bash
BRUH_APP_ENV=prod ./scripts/run_x_scrape_service.sh
```

Point the function to it:

```bash
export BRUH_X_INGEST_PROVIDER=self_hosted_service
export BRUH_X_SELF_HOSTED_SERVICE_URL=http://127.0.0.1:8789/fetch
export BRUH_X_SELF_HOSTED_SERVICE_TOKEN=replace-me
```

Then call the ingest function as usual.

## Deployment Notes

- On the self-hosted server, `ingest-x-posts` can call the crawler over `127.0.0.1`, so the crawler does not need a public port.
- If the current `twitter` CLI becomes unstable, this service is the intended swap point for a future Playwright-based crawler.
- The main function keeps the database contract stable, so crawler experiments stay isolated behind the service boundary.

## Practical Limitation

Moving off `Apify` removes the billing and card dependency, but it does not remove X scraping risk itself. The remaining operational risks are:

- cookie/login expiry
- account or IP rate limiting
- proxy needs if traffic grows
- DOM or endpoint changes if the underlying scraper implementation changes
