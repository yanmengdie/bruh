# Content Governance

## Goal

Add a lightweight safety layer around generated text and externally ingested content without changing the current UI or product flow.

## Current Coverage

Shared module:

- `supabase/functions/_shared/content_safety.ts`

Generated content paths:

- `generate-message`
- `message-starters`
- `generate-post-interactions`

External ingestion paths:

- `ingest-top-news`
- `ingest-x-posts`
- `ingest-xhs-posts`

## What The Safety Layer Does

- removes control characters and zero-width junk
- strips ordinary HTML tags from inbound text
- blocks dangerous markup such as `script`, `iframe`, `object`, `embed`, `svg`, `meta`, `link`, and `javascript:` payloads
- blocks obvious prompt-injection patterns such as `ignore previous instructions` or attempts to reveal hidden/system prompts
- blocks model-leakage phrases in generated text such as `as an AI language model` and direct assistant self-identification
- caps unusually long text with deterministic truncation

## Runtime Policy

Generated text:

- sanitize first
- if the result is blocked, fall back to the existing deterministic reply/comment path
- if fallback text is also unsafe, use a short generic safe sentence

External content:

- sanitize before it enters `source_posts` or `news_articles`
- drop entries whose core text is unsafe or empty after cleanup
- if a news summary is unsafe but the headline is safe, keep the article with the sanitized headline and degrade summary to the headline
- keep raw product behavior unchanged for end users wherever a safe fallback is available

## Observability

The affected functions now emit structured logs when content is:

- sanitized
- blocked
- replaced with fallback text

This keeps the policy operationally visible without introducing a heavy moderation product surface.
