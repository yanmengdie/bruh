# API Versioning

## Scope

The iOS app and the Supabase Edge Functions now use an explicit contract header handshake for the four app-facing endpoints:

- `feed.v1`
- `generate-message.v1`
- `message-starters.v1`
- `generate-post-interactions.v1`

Current server version:

- `2026-04-12`

Current compatibility mode:

- `additive`

## Request / Response Headers

Client requests send:

- `X-Bruh-Client-Version`
- `X-Bruh-Accept-Contract`

Server responses return:

- `X-Bruh-Server-Version`
- `X-Bruh-Contract`
- `X-Bruh-Compat-Mode`

Behavior:

- Missing request headers are treated as legacy-compatible, so older app builds are not broken immediately.
- If the client explicitly asks for a different contract than the endpoint serves, the function returns `412` with `errorCategory: validation`.
- If the server returns a successful response whose declared contract does not match the client expectation, `APIClient` fails before DTO decoding.

## DTO Compatibility Rules

Within the current `v1` contracts, only additive changes are allowed:

- adding optional fields is allowed
- preserving existing field meaning is required
- removing or renaming fields requires keeping a compatibility alias

Current iOS decoder compatibility covers both canonical camelCase and selected legacy aliases:

- snake_case response keys for feed, message, starter, and feed interaction DTOs
- `content` / `text` aliasing for message replies
- `sourceUrl` / `articleUrl` aliasing for starter source links
- `topSummary` / `top_summary` aliasing for starter summary payloads

## Rollout Rule

When changing a DTO:

1. Add the new field or alias on the backend first.
2. Keep the previous field shape working for at least one shipped client cycle.
3. Add or update Swift smoke coverage in `scripts/api_contract_smoke.swift`.
4. Only then clean up deprecated aliases in a later contract version.

## Non-Goals

This layer does not introduce user-visible UI changes or endpoint envelope rewrites. Array endpoints such as `feed` remain arrays; version metadata lives in headers to avoid breaking existing clients.
