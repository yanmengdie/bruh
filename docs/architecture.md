# Bruh Architecture

## 1. Scope

This document describes the current runtime architecture of the repository and the intended module boundaries after the `P0` stabilization work.

The system is split into four layers:

1. Persona catalog
2. iOS app state and presentation
3. Local content graph
4. Self-hosted content and generation pipeline

The main rule is:

- Persona definition is shared metadata.
- Backend owns remote content generation and ingestion.
- iOS owns local user state and channel presentation.
- Content graph is the bridge between raw content and user-facing surfaces.

## 2. Top-Level Modules

### Persona Catalog

Source of truth:

- `bruh/SharedPersonas.json`

Consumers:

- Swift persona seeding and local contact setup
- `supabase/functions/_shared/personas.ts`
- prompt/persona behavior helpers in `skills/` and backend `_shared/`

Boundary:

- This layer defines identity and metadata only.
- It should not own runtime message state, feed state, or delivery visibility.

Owns:

- `personaId`
- display name / handle / avatar / theme
- domains / trigger keywords / social circle / voice defaults

Does not own:

- whether a persona is accepted by the user
- latest messages
- feed delivery state
- runtime unread counts

### iOS App Layer

Main entry path:

- `bruh/bruhApp.swift`
- `bruh/ContentView.swift`
- `bruh/Services/AppBootstrapper.swift`

Responsibilities:

- app shell and navigation
- onboarding and local user profile state
- contacts / message threads / local interaction state
- persisting backend results into SwiftData
- rendering feed, messages, album, contacts, settings

Key services:

- `MessageService`: message send, starter sync, local thread normalization
- `FeedService`: feed refresh from backend DTOs into `PersonaPost`
- `FeedInteractionService`: feed like/comment interaction lifecycle
- `ContentGraphSelectors`: shared visibility/filter logic
- `AppBootstrapper`: startup orchestration

Boundary:

- Views should not reimplement content eligibility rules.
- Services should not own persona metadata definitions.
- UI reads from SwiftData-backed local models, not directly from backend response state after the request completes.

### Local Content Graph

Core models:

- `SourceItem`
- `ContentEvent`
- `ContentDelivery`

Producer:

- `ContentGraphStore` in `bruh/Models/SourceItem.swift`

Purpose:

- normalize raw posts and incoming messages into a single local graph
- separate canonical event identity from channel-specific rendering
- support feed, message, and album surfaces from shared local state

Conceptual roles:

- `SourceItem`: raw or near-raw upstream artifact
- `ContentEvent`: canonical semantic event
- `ContentDelivery`: channel projection of that event

Current event kinds:

- `socialPost`
- `messageStarter`
- `messageReply`
- `generatedImage`

Current delivery channels:

- `feed`
- `message`
- `album`

Boundary:

- `PersonaPost` and `PersonaMessage` are legacy/product-facing local records.
- `ContentGraphStore` is the only place that should translate those records into graph objects.
- channel-specific visibility rules belong in selectors or graph policy, not in views.

### Self-Hosted Backend Pipeline

Storage:

- `source_posts`
- `feed_items`
- `news_events`
- `persona_news_scores`
- interaction tables used by feed comments/likes

Runtime:

- PostgreSQL 16 on the self-hosted server
- PostgREST-compatible REST gateway for `supabase-js` compatibility
- function gateway that exposes app-facing endpoints under `/functions/v1`
- systemd services for each backend function
- cron-driven ingestion/build jobs on the server

Functions:

- `feed`
- `build-feed`
- `generate-message`
- `message-starters`
- `generate-post-interactions`
- ingestion functions for top news / X / XHS

Boundary:

- Backend owns external ingestion, ranking, prompt assembly, and remote generation.
- The repo still uses `supabase/functions` and `supabase-js` naming for compatibility, but the runtime can target a self-hosted PostgREST gateway instead of hosted Supabase.
- Backend shared helpers also own content-safety normalization for generated text and external input before it is reused as prompt context.
- Backend shared helpers also own request/job observability primitives such as `requestId`, structured terminal events, and duration logging.
- iOS should consume stable DTOs only.
- app-facing endpoints should declare contract/version metadata in headers; see `docs/api-versioning.md`.
- Backend should not rely on client-side seed/demo assumptions.

## 3. Primary Data Flows

### Persona Bootstrap Flow

1. App launches.
2. `AppBootstrapper` seeds persona metadata, user profile, and contacts.
3. Optional debug/demo runtime flags decide whether bundled moments or demo ordering are applied.
4. Message threads are normalized.
5. Remote starters are fetched once accepted contacts exist.

### Feed Flow

1. Backend ingestion writes `source_posts`.
2. `build-feed` projects `source_posts` into `feed_items` when needed.
3. `feed` returns feed DTOs in client-facing camelCase.
4. `FeedService` maps DTOs into `PersonaPost`.
5. `ContentGraphStore.syncFeedPost` writes or updates `SourceItem`, `ContentEvent`, and `ContentDelivery`.
6. Feed UI reads local graph-backed state rather than holding backend payloads directly.

### Message Flow

1. User sends a message through `MessageService`.
2. `generate-message` reads backend context and returns a reply DTO.
3. iOS persists the result into `PersonaMessage`.
4. `ContentGraphStore.syncIncomingMessage` projects that message into event and delivery records.
5. Message list, thread detail, and album all read from local state derived from the same incoming message.

### Starter Flow

1. `message-starters` reads `news_events` and `persona_news_scores`.
2. It returns starter DTOs per accepted persona.
3. iOS stores starters as seed `PersonaMessage` rows.
4. Those rows are projected into message deliveries and optionally album deliveries through the content graph.

### Feed Interaction Flow

1. Feed card requests interaction state for a post target.
2. `generate-post-interactions` returns transient interaction DTOs for the current iOS flow.
3. iOS persists local `FeedLike` and `FeedComment` rows.
4. Local runtime options control whether fallback synthetic interactions are allowed.

## 4. Ownership Boundaries

### Persona Layer Owns

- shared persona metadata
- prompt/personality defaults
- social-circle hints

### iOS Layer Owns

- onboarding completion
- selected interests
- accepted / pending / ignored contacts
- message threads and read state
- local feed interaction state
- local projections of backend content

### Content Graph Owns

- mapping from raw content to canonical events
- mapping from canonical events to feed/message/album deliveries
- delivery ids and event ids

### Backend Owns

- external ingestion
- feed ranking inputs
- persona-news matching
- remote text/image/voice generation
- database/job coordination for the self-hosted runtime

## 5. Backend Storage Responsibilities

### `source_posts`

Writer:

- `ingest-x-posts`
- `ingest-xhs-posts`

Readers:

- `build-feed`
- `feed`
- `generate-message` fallback context path

Role:

- Canonical store for persona-authored raw or near-raw upstream posts.
- This table should keep the original post identity and source metadata.
- It is not the place for ranked feed projections or normalized news clusters.

### `feed_items`

Writer:

- `build-feed`

Readers:

- `feed`
- `generate-message` primary recent-context path

Role:

- Rebuildable projection layer for the user-facing feed.
- It exists to support feed ordering and client DTO shaping without mutating `source_posts`.
- If it drifts or is empty, it should be safe to rebuild from `source_posts`.

### `news_events`

Writer:

- `build-news-events`
  upstream source comes from `news_articles` written by `ingest-top-news`

Readers:

- `message-starters`
- `generate-message` through persona-news joins and summary context

Role:

- Normalized, de-duplicated event layer for global/top news.
- Each row should represent an event cluster, not a persona-specific opinion and not a raw article row.

### `persona_news_scores`

Writer:

- `build-news-events`

Readers:

- `message-starters`
- `generate-message`

Role:

- Persona-to-news ranking join table.
- This is the only layer that should encode why a given persona is relevant to a given news event.
- Client-facing flows should read from it, but should not write into it.

### Supporting Tables

- `news_articles` is the raw ingest layer for RSS/news fetches.
- `news_event_articles` is the join table from clustered events back to raw articles.

Current rule of thumb:

- raw ingest stays raw
- rebuildable projections stay rebuildable
- persona ranking lives in join tables
- client DTO functions read stable projections, not mixed-purpose storage
- remote interaction generation

## 5. Current Design Constraints

- `PengyouMoment` is still a separate local lane and is not yet unified with the content graph.
- `PersonaPost` and `PersonaMessage` still exist as product-facing local records; the graph is a projection layer, not yet the only persisted truth.
- feed interactions are still locally persisted in iOS even when generated remotely.
- runtime demo/fallback behavior is now gated, but configuration injection is still incomplete.

## 6. Refactor Guardrails

- Do not let views decide message/feed/album eligibility independently.
- Do not add new backend DTO fields without updating the iOS decoding contract.
- Do not bypass `ContentGraphStore` when creating new user-facing content records.
- Do not put demo or seed behavior back into unconditional startup paths.
- Keep persona metadata changes in the shared catalog instead of copying them into runtime services.

## 7. Near-Term Direction

After `P0`, the next architectural priorities are:

1. Split `generate-message` into smaller backend modules.
2. move API base URL and key configuration out of hardcoded client defaults
3. add contract tests around DTOs and graph reconciliation
4. formalize environment separation between dev, staging, and prod
