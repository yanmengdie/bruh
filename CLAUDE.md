# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**Bruh** is a SwiftUI iOS app where users chat with AI-powered personas (public figures, personalities) and browse a curated social content feed. It pairs a SwiftUI/SwiftData frontend with a Supabase-compatible backend (PostgreSQL + Deno Edge Functions) and ingestion scripts.

## Build & Run Commands

```bash
# Build and launch on simulator (boots simulator, builds to .build/, installs, launches)
./run.sh "iPhone 17"

# Build-only check
xcodebuild -project bruh.xcodeproj -scheme bruh \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -derivedDataPath .build build

# Deploy a single Edge Function
supabase functions deploy generate-message   # or feed, message-starters, etc.

# Apply pending DB migrations
supabase db push

# Serve Edge Functions locally for testing
supabase functions serve
```

There is no XCTest target. Validate iOS changes by building + smoke-testing on simulator. Validate Edge Function changes with `curl` or `supabase functions serve`.

## Architecture

**iOS (SwiftUI + SwiftData)**
- `bruh/bruhApp.swift` — entry point; sets up SwiftData `ModelContainer`, seeds personas from `SharedPersonas.json` and `SeedData.swift` on first launch
- `bruh/ContentView.swift` — root navigation; switches between tab bar mode and home-screen mode
- `bruh/Networking/APIClient.swift` — actor-based async/await REST client; all calls go to Supabase Edge Functions
- `bruh/Models/` — SwiftData `@Model` classes: `Persona`, `MessageThread`, `PersonaMessage`, `SourceItem`, `PersonaPost`, `FeedComment`, `FeedLike`
- `bruh/Services/` — business logic; `MessageService`, `FeedService`, `FeedInteractionService` own side effects; views stay declarative
- `bruh/Views/` — feature screens: `Home/`, `Messages/`, `Contacts/`, `Feed/`, `Onboarding/`, plus `Components/` for reusables

**Backend (Supabase)**
- `supabase/functions/generate-message/` — core AI reply: resolves persona, fetches context, calls OpenAI, optionally generates image (Replicate) or TTS voice
- `supabase/functions/message-starters/` — generates 3–5 conversation starters per persona based on user interests + recent news
- `supabase/functions/feed/` — returns paginated feed posts sorted by importance + recency
- `supabase/functions/ingest-*/` — ingestion handlers called by scripts or cron; write to `source_items`/`content_events` tables
- `supabase/migrations/` — authoritative DB schema; run `supabase db push` to apply
- Shared helpers in `supabase/functions/_shared/`

**Ingestion**
- `scripts/ingest_x.py` — fetches Twitter/X posts via `twitter-cli`, upserts to Supabase
- `scripts/ingest_weibo.py` — fetches configured Weibo posts with an operator-provided cookie

**Persona Assets**
- `SharedPersonas.json` — catalog of persona metadata (handle, avatar, domains, themes); seeded into SwiftData on first launch
- `skills/` — persona prompt assets; several subfolders are **nested Git repos**, handle carefully
- `voice/` — pre-recorded persona voice `.mp3` files

## Coding Conventions

- Swift: 4-space indent, `UpperCamelCase` types, `lowerCamelCase` properties/functions
- Keep SwiftUI views declarative; push side effects into `Services/`
- TypeScript Edge Functions: small focused files, shared utilities in `_shared/`
- Match existing JSON field names exactly when changing API contracts (`personaId`, `imageUrl`, `sourcePostIds`, etc.)

## Security Note

`scripts/ingest_x.py` contains hardcoded service-role keys and Twitter auth tokens — do not commit real values. Sanitize before any future commit.
