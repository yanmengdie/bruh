# Error Recovery Policy

## Scope

This project now keeps error recovery focused on transport and upstream instability without changing any user-visible interface flow.

## iOS Request Policy

- `feed` reads retry up to 3 attempts.
- `message-starters` prefetch retries up to 3 attempts.
- `generate-message` sends retry up to 2 attempts.
- `generate-post-interactions` retries up to 2 attempts.

Retries only happen for transient cases:

- transport failures such as timeout, DNS lookup failure, offline, host lookup failure, or dropped connections
- HTTP `408`, `429`, `500`, `502`, `503`, `504`
- backend responses explicitly classified as `network`, `timeout`, `provider`, or `unknown`

Retries do not run for terminal categories:

- `validation`
- `auth`
- `config`
- `database`
- local decode or invalid URL failures

## Starter Bootstrap Recovery

- Local starter seeding still runs first so the app remains usable without waiting for the backend.
- Remote starter refresh is only marked as complete after a successful remote fetch.
- If the refresh fails, bootstrap does not permanently lock the session into fallback mode.
- Failed bootstrap refreshes enter a 20 second cooldown and can retry on the next bootstrap trigger.

## Backend Recovery Signals

- `feed` now returns structured `errorCategory` values on failures, so the client can distinguish transient failures from terminal ones.
- `feed` and `build-feed` now emit structured success and failure logs with `requestId`.
- `build-feed` still relies on the existing pipeline lock + next cron tick/manual rerun model from `docs/pipeline-jobs.md`; this remains the recovery path for pipeline execution failures.
