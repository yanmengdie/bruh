#!/usr/bin/env python3
"""
Fetch latest posts from persona Twitter accounts and upsert to Supabase.
Only fetches posts newer than the last successful run per user.
Usage: python scripts/ingest_x.py
"""

import json
import os
import re
import subprocess
import sys
import urllib.request
from datetime import datetime, timezone

# ── Config ────────────────────────────────────────────────────────────────────

def normalize_app_env(raw_value: str | None) -> str:
    normalized = (raw_value or "").strip().lower()
    if normalized in {"", "dev", "development", "local", "debug"}:
        return "dev"
    if normalized in {"staging", "stage", "stg", "qa", "test"}:
        return "staging"
    if normalized in {"prod", "production", "release", "live"}:
        return "prod"
    return "dev"


APP_ENV = normalize_app_env(os.environ.get("BRUH_APP_ENV") or os.environ.get("BRUH_ENV"))


def resolve_env(*keys: str, default: str | None = None, required: bool = False) -> str | None:
    suffix = APP_ENV.upper()
    for key in keys:
        for candidate in (f"{key}__{suffix}", key):
            value = os.environ.get(candidate)
            if value and value.strip():
                return value.strip()

    if required:
        candidates = ", ".join([*(f"{key}__{suffix}" for key in keys), *keys])
        raise RuntimeError(f"Missing environment variable. Looked for: {candidates}")

    return default


SUPABASE_URL = resolve_env("SUPABASE_URL", "PROJECT_URL")
SUPABASE_SERVICE_ROLE_KEY = resolve_env("SUPABASE_SERVICE_ROLE_KEY", "SERVICE_ROLE_KEY")

TWITTER_AUTH_TOKEN = resolve_env("TWITTER_AUTH_TOKEN")
TWITTER_CT0 = resolve_env("TWITTER_CT0")

HTTP_PROXY = resolve_env("HTTP_PROXY", default="")
HTTPS_PROXY = resolve_env("HTTPS_PROXY", default="")

PERSONAS = {
    "elonmusk": "musk",
    "realdonaldtrump": "trump",
}

# Fetch this many posts per user each run — large enough to cover bursts
FETCH_LIMIT = int(resolve_env("FETCH_LIMIT", default="200") or "200")

# State file: tracks the newest post timestamp seen per user
STATE_FILE = os.path.expanduser("~/.bruh-ingest-state.json")

# ── State (last-seen timestamps) ──────────────────────────────────────────────

def load_state() -> dict[str, str]:
    try:
        with open(STATE_FILE) as f:
            return json.load(f)
    except (FileNotFoundError, json.JSONDecodeError):
        return {}

def save_state(state: dict[str, str]) -> None:
    with open(STATE_FILE, "w") as f:
        json.dump(state, f, indent=2)

# ── Twitter fetch ─────────────────────────────────────────────────────────────

def fetch_user_posts(username: str, limit: int) -> list[dict]:
    env = {**os.environ}
    if TWITTER_AUTH_TOKEN:
        env["TWITTER_AUTH_TOKEN"] = TWITTER_AUTH_TOKEN
    if TWITTER_CT0:
        env["TWITTER_CT0"] = TWITTER_CT0
    if HTTP_PROXY:
        env["HTTP_PROXY"] = HTTP_PROXY
    if HTTPS_PROXY:
        env["HTTPS_PROXY"] = HTTPS_PROXY

    twitter_bin = resolve_env("TWITTER_BIN", default="twitter") or "twitter"
    result = subprocess.run(
        [twitter_bin, "user-posts", f"@{username}", "-n", str(limit), "--json"],
        capture_output=True,
        text=True,
        env=env,
        timeout=60,
    )

    if result.returncode != 0:
        print(f"  [error] twitter-cli stderr: {result.stderr[:200]}", file=sys.stderr)
        return []

    try:
        parsed = json.loads(result.stdout)
    except Exception as e:
        print(f"  [error] parse failed: {e}", file=sys.stderr)
        return []

    if not parsed or not parsed.get("ok"):
        err = parsed.get("error", {}) if parsed else {}
        print(f"  [error] {err.get('message', 'unknown error')}", file=sys.stderr)
        return []

    return parsed.get("data", [])

# ── Normalize ─────────────────────────────────────────────────────────────────

def parse_dt(value: str) -> datetime | None:
    try:
        return datetime.fromisoformat(value.replace("Z", "+00:00"))
    except Exception:
        return None

def compute_importance(post: dict) -> float:
    m = post.get("metrics", {})
    likes = m.get("likes", 0) or 0
    retweets = m.get("retweets", 0) or 0
    replies = m.get("replies", 0) or 0
    quotes = m.get("quotes", 0) or 0
    views = m.get("views", 0) or 0
    raw = 0.5 + min((likes + retweets * 2 + replies + quotes + views / 10000) / 1000, 0.49)
    return round(raw, 2)

def is_retweet(post: dict) -> bool:
    return post.get("isRetweet", False) or str(post.get("text", "")).startswith("RT @")

def is_low_quality(post: dict) -> bool:
    if is_retweet(post):
        return True
    text = post.get("text", "")
    cleaned = re.sub(r"https?://\S+", " ", text)
    cleaned = re.sub(r"@\w+", " ", cleaned).strip()
    return len(cleaned) < 12

def normalize(post: dict, username: str, persona_id: str) -> tuple[dict, datetime] | None:
    if is_low_quality(post):
        return None

    post_id = str(post.get("id", ""))
    if not post_id:
        return None

    text = post.get("text", "").strip()
    if not text:
        return None

    created_iso = post.get("createdAtISO") or post.get("createdAt")
    if not created_iso:
        return None

    dt = parse_dt(created_iso)
    if dt is None:
        return None

    source_url = f"https://x.com/{username}/status/{post_id}"

    row = {
        "id": post_id,
        "persona_id": persona_id,
        "source_type": "x",
        "content": text,
        "source_url": source_url,
        "topic": None,
        "importance_score": compute_importance(post),
        "published_at": dt.isoformat(),
        "raw_author_username": username,
        "raw_payload": post,
    }
    return row, dt

# ── Supabase upsert ───────────────────────────────────────────────────────────

def supabase_upsert(rows: list[dict]) -> dict:
    if not SUPABASE_URL or not SUPABASE_SERVICE_ROLE_KEY:
        return {"ok": False, "status": 500, "error": "Missing Supabase environment variables"}

    payload = json.dumps(rows).encode()
    req = urllib.request.Request(
        f"{SUPABASE_URL}/rest/v1/source_posts?on_conflict=id",
        data=payload,
        method="POST",
        headers={
            "Content-Type": "application/json",
            "Authorization": f"Bearer {SUPABASE_SERVICE_ROLE_KEY}",
            "apikey": SUPABASE_SERVICE_ROLE_KEY,
            "Prefer": "resolution=merge-duplicates,return=minimal",
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=15) as resp:
            return {"ok": True, "status": resp.status}
    except urllib.error.HTTPError as e:
        body = e.read().decode()
        return {"ok": False, "status": e.code, "error": body}

# ── Main ──────────────────────────────────────────────────────────────────────

def main():
    print(f"Environment: {APP_ENV}")
    if not SUPABASE_URL or not SUPABASE_SERVICE_ROLE_KEY:
        raise RuntimeError(
            "Missing Supabase configuration. Set SUPABASE_URL/PROJECT_URL and "
            "SUPABASE_SERVICE_ROLE_KEY/SERVICE_ROLE_KEY, optionally with __DEV/__STAGING/__PROD suffixes."
        )
    state = load_state()
    new_state = dict(state)
    total_new = 0
    total_skipped = 0

    for username, persona_id in PERSONAS.items():
        last_seen_str = state.get(username)
        last_seen = parse_dt(last_seen_str) if last_seen_str else None

        print(f"\n→ @{username} ({persona_id})")
        if last_seen:
            print(f"  last seen: {last_seen.strftime('%Y-%m-%d %H:%M UTC')}")
        else:
            print(f"  first run — no baseline yet")

        posts = fetch_user_posts(username, FETCH_LIMIT)
        print(f"  fetched: {len(posts)}")

        results = [normalize(p, username, persona_id) for p in posts]
        valid = [(row, dt) for r in results if r is not None for row, dt in [r]]

        # Filter to only posts newer than last seen
        if last_seen:
            new_valid = [(row, dt) for row, dt in valid if dt > last_seen]
            print(f"  newer than last run: {len(new_valid)}  already seen: {len(valid) - len(new_valid)}")
        else:
            new_valid = valid
            print(f"  normalized: {len(new_valid)}  low-quality: {len(posts) - len(valid)}")

        total_skipped += len(posts) - len(new_valid)

        if not new_valid:
            print(f"  nothing new")
            continue

        rows = [row for row, _ in new_valid]
        result = supabase_upsert(rows)
        if result["ok"]:
            print(f"  upserted: {len(rows)} rows ✓")
            total_new += len(rows)
            # Update state to the newest post timestamp seen this run
            newest_dt = max(dt for _, dt in new_valid)
            new_state[username] = newest_dt.isoformat()
        else:
            print(f"  upsert error {result['status']}: {result.get('error', '')[:200]}", file=sys.stderr)

    save_state(new_state)
    print(f"\n✓ done — new: {total_new}, skipped: {total_skipped}")
    print(f"  state saved → {STATE_FILE}")

if __name__ == "__main__":
    main()
