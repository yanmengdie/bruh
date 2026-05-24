# Environment Setup

## Goal

The repo supports explicit `dev`, `staging`, and `prod` configuration without changing UI code.

All runtime config follows the same rule:

- pick the current environment from `BRUH_APP_ENV`
- read `KEY__<ENV>` first
- fall back to `KEY`

## iOS App

`bruh` resolves `BRUH_APP_ENV` from:

1. process environment
2. generated `Info.plist`
3. build default: `dev` for Debug, `prod` for Release

Supported app config keys:

- `BRUH_FUNCTIONS_BASE_URL` — backend API base URL (default: `http://8.141.119.22:3000/api`)
- `BRUH_SUPABASE_ANON_KEY` — compatibility key (unused by new backend, kept for compatibility)

Environment-scoped examples:

- `BRUH_FUNCTIONS_BASE_URL__DEV`
- `BRUH_FUNCTIONS_BASE_URL__STAGING`

## Backend

Backend runs on 8.141.119.22 with pm2. Configuration via `/opt/bruh-backend/.env`:

- `DATABASE_URL` — PostgreSQL connection string
- `OPENAI_API_KEY` — OpenAI-compatible API key
- `OPENAI_BASE_URL` — LLM base URL
- `OPENAI_MODEL` — LLM model name
- `VOICE_API_KEY` — MiMo TTS API key
- `VOICE_API_BASE_URL` — MiMo TTS base URL
- `PORT` — server port (default 3000)
