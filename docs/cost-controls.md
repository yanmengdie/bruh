# Cost Controls

## Goal

Add low-risk guardrails for expensive backend paths without changing the default product behavior.

Current defaults preserve existing behavior:

- LLM generation stays enabled
- TTS stays enabled with the existing `180` character gate
- message image generation stays enabled when requested
- X ingestion stays enabled
- X ingestion still allows the full default username set and up to `20` posts per user

## Supported Controls

All controls support the same `KEY__ENV -> KEY` lookup described in [environment-setup.md](./environment-setup.md).

- `BRUH_LLM_GENERATION_MODE`
  `enabled` or `fallback_only`
- `BRUH_TTS_MODE`
  `enabled`, `force_only`, or `disabled`
- `BRUH_TTS_MAX_CHARACTERS`
  clamps to `40...400`
- `BRUH_MESSAGE_IMAGE_MODE`
  `enabled` or `disabled`
- `BRUH_X_INGEST_MODE`
  `enabled` or `disabled`
- `BRUH_X_INGEST_MAX_USERNAMES_PER_RUN`
  clamps to the current persona-backed username count
- `BRUH_X_INGEST_MAX_POSTS_PER_USER`
  clamps to `1...20`

## Current Coverage

- `generate-message`
  supports LLM fallback-only mode, TTS degradation, and message image kill switch
- `message-starters`
  supports LLM fallback-only mode, so starter text generation can fall back to deterministic copy without external model calls
- `ingest-x-posts`
  supports full disable plus hard caps for usernames and posts per user

## Rollout Examples

Emergency model-cost rollback:

```bash
export BRUH_LLM_GENERATION_MODE__STAGING=fallback_only
export BRUH_MESSAGE_IMAGE_MODE__STAGING=disabled
```

Keep voice replies only for explicitly forced requests:

```bash
export BRUH_TTS_MODE__STAGING=force_only
export BRUH_TTS_MAX_CHARACTERS__STAGING=120
```

Reduce X scraping spend:

```bash
export BRUH_X_INGEST_MAX_USERNAMES_PER_RUN__STAGING=3
export BRUH_X_INGEST_MAX_POSTS_PER_USER__STAGING=4
```
