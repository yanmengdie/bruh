# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**Bruh** is a SwiftUI iOS app where users chat with AI-powered personas (public figures, personalities) and browse a curated social content feed. It pairs a SwiftUI/SwiftData frontend with a self-hosted Node.js backend (Express + PostgreSQL).

## Build & Run Commands

```bash
# Build and launch on simulator
./run.sh "iPhone 17"

# Build-only check
xcodebuild -project bruh.xcodeproj -scheme bruh \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -derivedDataPath .build build

# Backend (on server 8.141.119.22)
ssh root@8.141.119.22
cd /opt/bruh-backend
pm2 restart bruh-backend
```

There is no XCTest target. Validate iOS changes by building + smoke-testing on simulator.

## Architecture

**iOS (SwiftUI + SwiftData)**
- `bruh/bruhApp.swift` — entry point; sets up SwiftData `ModelContainer`, seeds personas from `SharedPersonas.json` and `SeedData.swift` on first launch
- `bruh/ContentView.swift` — root navigation; switches between tab bar mode and home-screen mode
- `bruh/Networking/APIClient.swift` — actor-based async/await REST client; calls go to self-hosted backend
- `bruh/Models/` — SwiftData `@Model` classes: `Persona`, `MessageThread`, `PersonaMessage`, `SourceItem`, `PersonaPost`, `FeedComment`, `FeedLike`
- `bruh/Services/` — business logic; `MessageService`, `FeedService`, `FeedInteractionService` own side effects; views stay declarative
- `bruh/Views/` — feature screens: `Home/`, `Messages/`, `Contacts/`, `Feed/`, `Onboarding/`, plus `Components/` for reusables

**Backend (Node.js + Express + PostgreSQL)**
- `backend/src/index.ts` — Express server entry with 4 API routes
- `backend/src/routes/` — route handlers for messages, feed, starters, interactions
- `backend/src/lib/` — shared modules: db, personas, llm, tts, prompts
- `backend/data/` — persona catalog (SharedPersonas.json) and voice samples
- `backend/sql/schema.sql` — consolidated database schema
- Deployed on 8.141.119.22 with pm2

**API Endpoints**
- `GET /api/feed` — paginated feed posts
- `POST /api/messages` — AI persona reply (+ optional TTS voice)
- `POST /api/starters` — conversation starters based on news
- `POST /api/interactions` — feed post likes/comments

**Persona Assets**
- `SharedPersonas.json` — catalog of persona metadata (handle, avatar, domains, themes); seeded into SwiftData on first launch
- `skills/` — persona prompt assets; several subfolders are **nested Git repos**, handle carefully

## Coding Conventions

- Swift: 4-space indent, `UpperCamelCase` types, `lowerCamelCase` properties/functions
- Keep SwiftUI views declarative; push side effects into `Services/`
- TypeScript backend: Express routes in `src/routes/`, shared utilities in `src/lib/`
- Match existing JSON field names exactly when changing API contracts (`personaId`, `imageUrl`, `sourcePostIds`, etc.)
