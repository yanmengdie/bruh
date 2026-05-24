# Repository Guidelines

## Project Structure & Module Organization
`bruh/` contains the iOS app. Core models live in `bruh/Models`, networking in `bruh/Networking`, app logic in `bruh/Services`, and SwiftUI screens in `bruh/Views`. Assets and launch resources live under `bruh/Assets.xcassets` and `bruh/LaunchScreen.storyboard`.  
`backend/` contains the self-hosted Node.js backend: Express server in `src/index.ts`, route handlers in `src/routes/`, shared modules in `src/lib/`, and database schema in `sql/schema.sql`.  
`scripts/` are CI and validation helpers. `skills/` stores persona prompt assets; several subfolders are nested Git repositories and should be handled carefully.

## Build, Test, and Development Commands
- `./run.sh "iPhone 17"`: boots the simulator, builds the app into `.build/`, installs, and launches it.
- `xcodebuild -project bruh.xcodeproj -scheme bruh -destination 'platform=iOS Simulator,name=iPhone 17' build`: canonical local build check.
- Backend runs on 8.141.119.22:3000, managed by pm2. SSH to restart or update.

## Coding Style & Naming Conventions
Use existing Swift conventions: 4-space indentation, `UpperCamelCase` for types, `lowerCamelCase` for properties/functions, and short focused files. Keep SwiftUI views declarative; move side effects into services.  
For backend TypeScript, use Express routes in `src/routes/` and shared utilities in `src/lib/`. Match existing JSON field names exactly when changing API contracts (`personaId`, `imageUrl`, `sourcePostIds`).

## Testing Guidelines
There is no dedicated XCTest target yet. Minimum validation is:
- build the iOS app with `xcodebuild`
- smoke-test on the iPhone 17 simulator
- verify backend endpoints with `curl http://8.141.119.22:3000/api/health`

When changing feed or message flows, test both local fallback behavior and live backend responses.

## Commit & Pull Request Guidelines
Recent history uses short imperative commits, often checkpoint-style or focused summaries. Prefer concise, descriptive messages explaining user-visible impact.  
PRs should include:
- a short summary of product behavior changed
- simulator screenshots for UI changes
- notes on backend changes or required secrets

## Security & Configuration Tips
Do not commit real tokens, API keys, or database credentials. Backend `.env` files are gitignored. Treat `skills/` nested repos as external content unless intentionally vendoring them.
