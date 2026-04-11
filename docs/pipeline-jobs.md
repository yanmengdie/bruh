# Pipeline Jobs

## Goal

Make scheduled ingestion/build jobs safe to re-run and safe against overlap.

## Current Guardrails

- scheduled write paths use database upserts instead of append-only inserts
- cron-triggered builders/ingestors now claim a shared database lock before work starts
- duplicate triggers return a skipped response instead of running concurrently
- success/failure state is written back to the lock row for the next run

## Locking

Migration:

- `supabase/migrations/0018_pipeline_job_locks.sql`

Runtime helper:

- `supabase/functions/_shared/pipeline_lock.ts`

Tracked fields:

- `job_name`
- `owner_id`
- `status`
- `locked_at`
- `expires_at`
- `last_started_at`
- `last_finished_at`
- `last_succeeded_at`
- `last_error`

## Locked Jobs

- `ingest-top-news`
- `build-news-events`
- `ingest-x-posts`
- `build-feed`

## Retry Model

- overlap retry: blocked immediately by `pipeline_job_locks`
- data retry: safe because write paths already use `upsert(...)`
- schedule retry: next cron tick can retry after TTL expiry or after the previous run marks completion
- manual retry: safe as long as the operator waits for the current lock to expire or complete

## Notes

- This is a baseline coordination layer, not a full workflow engine.
- `feed` is intentionally not locked because it is a read path.
- If a job crashes hard, the TTL on the lock row allows the next run to reclaim it.
