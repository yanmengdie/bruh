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

SUPABASE_URL = "https://mrxctelezutprdeemqla.supabase.co"
SUPABASE_SERVICE_ROLE_KEY = os.environ.get(
    "SUPABASE_SERVICE_ROLE_KEY",
    "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im1yeGN0ZWxlenV0cHJkZWVtcWxhIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc3NTQ5MTUxMywiZXhwIjoyMDkxMDY3NTEzfQ.0fqh2fasgqScEI4XFTqjQEYF7vwn45ZIw0ZYVG4bznU",
)

TWITTER_AUTH_TOKEN = os.environ.get("TWITTER_AUTH_TOKEN", "e60ac9253a730e8455d7fa53a752cdbe55afffb4")
TWITTER_CT0 = os.environ.get(
    "TWITTER_CT0",
    "1b93be1f4f3949092149d08112f7085e15d5cbe2a605c36d58ffc4e75b40eae30ad623a1f253c5d72bef36e728038e604ec9c23117e447cdbb86dc997cd48317a4219bed957f68e2cbda23b48ba3bb58",
)

HTTP_PROXY = os.environ.get("HTTP_PROXY", "http://127.0.0.1:33210")
HTTPS_PROXY = os.environ.get("HTTPS_PROXY", "http://127.0.0.1:33210")

PERSONAS = {
    "elonmusk": "musk",
    "realdonaldtrump": "trump",
    "finkd": "zuckerberg",
}

# Fetch this many posts per user each run — large enough to cover bursts
FETCH_LIMIT = int(os.environ.get("FETCH_LIMIT", "200"))

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
    env = {
        **os.environ,
        "TWITTER_AUTH_TOKEN": TWITTER_AUTH_TOKEN,
        "TWITTER_CT0": TWITTER_CT0,
        "HTTP_PROXY": HTTP_PROXY,
        "HTTPS_PROXY": HTTPS_PROXY,
    }

    twitter_bin = os.environ.get("TWITTER_BIN", "/Users/nayi/miniconda3/bin/twitter")
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
