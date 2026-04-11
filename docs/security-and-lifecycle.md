# Security And Lifecycle

## Goal

Establish a minimum operational baseline for secret hygiene, data retention, and backend cleanup without changing user-visible behavior by default.

## Security Baseline

- secrets must come from environment variables or Supabase secret storage
- `.env` files remain ignored by Git
- `scripts/check_sensitive_strings.sh` scans tracked code for common secret-like patterns before CI passes
- `scripts/check_client_boundary.sh` ensures the iOS app surface does not reference server-only secrets or provider credentials
- `skills/` content is treated as external material and is excluded from the repository secret scan to avoid noisy false positives
- `scripts/ingest_x.py` and Edge Functions now resolve credentials from the scoped environment layer instead of embedding prod defaults

Client/server boundary:

- iOS may embed only publishable / anon Supabase credentials
- service-role keys and model-provider secrets remain backend-only
- app-facing config keys such as `BRUH_SUPABASE_ANON_KEY` / `SUPABASE_ANON_KEY` are allowed on the client
- server-only keys such as `SERVICE_ROLE_KEY`, `SUPABASE_SERVICE_ROLE_KEY`, `OPENAI_API_KEY`, `ANTHROPIC_API_KEY`, `VOICE_API_KEY`, `NANO_BANANA_API_KEY`, `APIFY_TOKEN` must never appear in `bruh/` or the Xcode project file

Run locally:

```bash
./scripts/check_sensitive_strings.sh
./scripts/check_client_boundary.sh
```

## Content Governance Baseline

- `supabase/functions/_shared/content_safety.ts` is the shared lightweight interception layer for generated text and externally ingested text
- generated text in `generate-message`, `message-starters`, and `generate-post-interactions` is sanitized before returning or persisting
- external content in `ingest-top-news`, `ingest-x-posts`, and `ingest-xhs-posts` is sanitized before entering the main ranking / generation tables
- obvious prompt injection, assistant leakage, and dangerous HTML/script payloads are blocked instead of silently flowing into prompt context

See `docs/content-governance.md` for the concrete runtime policy.

## Retention Policy

Current recommended retention windows:

- `source_posts` and cascading `feed_items`: `30` days
- `news_events`, `persona_news_scores`, `news_event_articles`: `14` days through `news_events` cleanup
- `news_articles`: `14` days
- `pipeline_job_locks`: `30` days after completion

These are intentionally conservative defaults for now. They reduce storage drift and stale ranking artifacts without deleting active hot data immediately.

## Manual Cleanup Entry

Migration `0019_backend_retention_cleanup.sql` adds a manual RPC:

```sql
select * from public.run_backend_retention_cleanup();
```

Override windows if needed:

```sql
select *
from public.run_backend_retention_cleanup(
  p_source_post_days => 45,
  p_news_days => 21,
  p_pipeline_lock_days => 60
);
```

This function is not wired to cron yet. The current baseline is:

- define one cleanup entrypoint
- keep it service-role only
- document safe default windows first

That gives us lifecycle governance now without introducing silent automatic deletion before we observe real production usage.
