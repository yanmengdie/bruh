# Feature Flags

## Goal

Add a minimal rollout layer for backend behavior changes without changing the default user experience.

Current defaults preserve existing behavior:

- all personas enabled
- starter selection stays `balanced`
- starter image selection stays `adaptive`
- starter source URL selection stays `adaptive`
- feed reads stay `auto` (`source_posts` first, then `feed_items`)
- feed ranking stays `chronological`

## Supported Flags

All flags follow the same environment-scoped lookup rule described in [environment-setup.md](./environment-setup.md):

- `BRUH_ENABLED_PERSONA_IDS`
  comma-separated allowlist, for example `musk,sam_altman,trump`
- `BRUH_STARTER_SELECTION_STRATEGY`
  `balanced` or `global_only`
- `BRUH_STARTER_IMAGE_MODE`
  `adaptive` or `disabled`
- `BRUH_STARTER_SOURCE_URL_MODE`
  `adaptive`, `always`, or `never`
- `BRUH_FEED_READ_SOURCE`
  `auto`, `source_posts`, or `feed_items`
- `BRUH_FEED_RANKING_STRATEGY`
  `chronological` or `importance`

Alias also supported:

- `BRUH_PERSONA_ALLOWLIST` -> `BRUH_ENABLED_PERSONA_IDS`

## Rollout Examples

Staging canary for a smaller persona set:

```bash
export BRUH_APP_ENV=staging
export BRUH_ENABLED_PERSONA_IDS__STAGING=musk,sam_altman,zhang_peng
```

Safe rollback for starter generation when prompt quality regresses:

```bash
export BRUH_STARTER_SELECTION_STRATEGY__STAGING=global_only
export BRUH_STARTER_IMAGE_MODE__STAGING=disabled
export BRUH_STARTER_SOURCE_URL_MODE__STAGING=never
```

Feed fallback or ranking experiment:

```bash
export BRUH_FEED_READ_SOURCE__STAGING=feed_items
export BRUH_FEED_RANKING_STRATEGY__STAGING=importance
```

## Current Coverage

The current flag layer is wired into:

- `build-news-events`
  persona score generation only runs for enabled personas
- `message-starters`
  persona allowlist, starter selection mode, image mode, and source URL mode
- `feed`
  persona allowlist, data source choice, and ranking mode

This keeps rollout control on the backend side first, so we can change strategy safely without introducing default UI changes in the iOS app.
