# Repository Guidelines

## Project Structure & Module Organization
`bruh/` contains the iOS app. Core models live in `bruh/Models`, networking in `bruh/Networking`, app logic in `bruh/Services`, and SwiftUI screens in `bruh/Views`. Assets and launch resources live under `bruh/Assets.xcassets` and `bruh/LaunchScreen.storyboard`.  
`supabase/` contains backend infrastructure: SQL migrations in `supabase/migrations` and Edge Functions in `supabase/functions`.  
`tools/xhs/` and `scripts/` are ingestion helpers. `skills/` stores persona prompt assets; several subfolders are nested Git repositories and should be handled carefully.

## Build, Test, and Development Commands
- `./run.sh "iPhone 17"`: boots the simulator, builds the app into `.build/`, installs, and launches it.
- `xcodebuild -project bruh.xcodeproj -scheme bruh -destination 'platform=iOS Simulator,name=iPhone 17' build`: canonical local build check.
- `supabase functions deploy <name>`: deploy a single Edge Function, for example `generate-message` or `feed`.
- `supabase db push`: apply pending migrations to the linked Supabase project.

## Coding Style & Naming Conventions
Use existing Swift conventions: 4-space indentation, `UpperCamelCase` for types, `lowerCamelCase` for properties/functions, and short focused files. Keep SwiftUI views declarative; move side effects into services.  
For Supabase functions, use TypeScript with small helpers in `_shared/`. Match existing JSON field names exactly when changing API contracts (`personaId`, `imageUrl`, `sourcePostIds`).

## Testing Guidelines
There is no dedicated XCTest target yet. Minimum validation is:
- build the iOS app with `xcodebuild`
- smoke-test on the iPhone 17 simulator
- verify changed Edge Functions with `curl` or `supabase functions serve/deploy`

When changing feed or message flows, test both local fallback behavior and live backend responses.

## Commit & Pull Request Guidelines
Recent history uses short imperative commits, often checkpoint-style (`checkpoint v3`) or focused summaries (`Stabilize startup and preserve persona prompts`). Prefer concise, descriptive messages explaining user-visible impact.  
PRs should include:
- a short summary of product behavior changed
- simulator screenshots for UI changes
- notes on backend migrations or required secrets

## Security & Configuration Tips
Do not commit real tokens, cookies, or service-role keys. `scripts/ingest_x.py` currently contains sensitive defaults and should be sanitized before any future commit. Treat `skills/` nested repos as external content unless intentionally vendoring them.
