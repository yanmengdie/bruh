#!/usr/bin/env python3
"""
Self-hosted X scrape service for ingest-x-posts.

Endpoints:
  GET  /health
  POST /fetch

The service intentionally does not write to the database. It only fetches and
normalizes recent X posts so the main ingest function can keep owning content
quality checks, dedupe, and source_posts writes.
"""

from __future__ import annotations

import json
import os
import re
import subprocess
import sys
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path


ROOT_DIR = Path(__file__).resolve().parents[1]
PERSONA_FILE = ROOT_DIR / "bruh" / "SharedPersonas.json"


def normalize_app_env(raw_value: str | None) -> str:
    normalized = (raw_value or "").strip().lower()
    if normalized in {"", "dev", "development", "local", "debug"}:
        return "dev"
    if normalized in {"staging", "stage", "stg", "qa", "test"}:
        return "staging"
    if normalized in {"prod", "production", "release", "live"}:
        return "prod"
    return "prod"


APP_ENV = normalize_app_env(
    os.environ.get("BRUH_APP_ENV")
    or os.environ.get("BRUH_ENV")
    or os.environ.get("DEPLOY_ENV")
    or os.environ.get("ENVIRONMENT")
)


def resolve_env(*keys: str, default: str | None = None) -> str | None:
    suffix = APP_ENV.upper()
    for key in keys:
        for candidate in (f"{key}__{suffix}", key):
            value = os.environ.get(candidate)
            if value and value.strip():
                return value.strip()
    return default


SERVICE_HOST = resolve_env(
    "BRUH_X_SELF_HOSTED_SERVICE_HOST",
    "X_INGEST_SERVICE_HOST",
    default="127.0.0.1",
) or "127.0.0.1"
SERVICE_PORT = int(
    resolve_env(
        "BRUH_X_SELF_HOSTED_SERVICE_PORT",
        "X_INGEST_SERVICE_PORT",
        default="8789",
    )
    or "8789"
)
SERVICE_TOKEN = resolve_env(
    "BRUH_X_SELF_HOSTED_SERVICE_TOKEN",
    "X_INGEST_SERVICE_TOKEN",
    "BRUH_X_SCRAPER_SERVICE_TOKEN",
)
REQUEST_TIMEOUT_SECONDS = int(
    resolve_env(
        "BRUH_X_SELF_HOSTED_REQUEST_TIMEOUT_SECONDS",
        "X_INGEST_REQUEST_TIMEOUT_SECONDS",
        default="60",
    )
    or "60"
)
DEFAULT_LIMIT_PER_USER = int(
    resolve_env(
        "BRUH_X_SELF_HOSTED_DEFAULT_LIMIT",
        "X_INGEST_DEFAULT_LIMIT",
        default="5",
    )
    or "5"
)

TWITTER_AUTH_TOKEN = resolve_env("TWITTER_AUTH_TOKEN")
TWITTER_CT0 = resolve_env("TWITTER_CT0")
HTTP_PROXY = resolve_env("HTTP_PROXY", default="")
HTTPS_PROXY = resolve_env("HTTPS_PROXY", default="")
TWITTER_BIN = resolve_env("TWITTER_BIN", default="twitter") or "twitter"


def normalize_username(value: str) -> str:
    return value.replace("@", "").strip().lower()


def load_persona_map() -> dict[str, str]:
    try:
        payload = json.loads(PERSONA_FILE.read_text(encoding="utf-8"))
    except FileNotFoundError as exc:
        raise RuntimeError(f"Missing persona file: {PERSONA_FILE}") from exc

    mapping: dict[str, str] = {}
    for record in payload:
        persona_id = str(record.get("id", "")).strip()
        if not persona_id:
            continue

        for account in record.get("platformAccounts", []):
            if not isinstance(account, dict):
                continue
            if str(account.get("platform", "")).strip().lower() != "x":
                continue
            if account.get("isActive", True) is False:
                continue

            handle = normalize_username(str(account.get("handle", "")))
            if handle:
                mapping[handle] = persona_id

    return mapping


PERSONA_MAP = load_persona_map()


def parse_dt(value: str) -> datetime | None:
    try:
        return datetime.fromisoformat(value.replace("Z", "+00:00"))
    except Exception:
        return None


def as_number(value: object) -> float:
    if isinstance(value, (int, float)):
        return float(value)
    if isinstance(value, str):
        try:
            return float(value.replace(",", ""))
        except ValueError:
            return 0.0
    return 0.0


def compute_importance(post: dict) -> float:
    metrics = post.get("metrics") if isinstance(post.get("metrics"), dict) else {}
    likes = as_number(metrics.get("likes") or post.get("likeCount") or post.get("favoriteCount"))
    retweets = as_number(metrics.get("retweets") or post.get("retweetCount") or post.get("repostCount"))
    replies = as_number(metrics.get("replies") or post.get("replyCount"))
    quotes = as_number(metrics.get("quotes") or post.get("quoteCount"))
    views = as_number(metrics.get("views") or post.get("viewCount"))
    raw = 0.5 + min((likes + retweets * 2 + replies + quotes + views / 10000) / 1000, 0.49)
    return round(raw, 2)


def is_retweet(post: dict) -> bool:
    text = str(post.get("text", "")).strip()
    return bool(post.get("isRetweet")) or text.startswith("RT @")


def normalize_content_for_quality_check(content: str) -> str:
    return re.sub(r"\s+", " ", re.sub(r"https?://\S+|@\w+|[#*_`~]", " ", content)).strip()


def extract_media_entries(post: dict) -> list[dict]:
    entries: list[dict] = []
    for key in ("media", "photos", "images"):
        value = post.get(key)
        if isinstance(value, list):
            entries.extend(item for item in value if isinstance(item, dict))
    return entries


def extract_media_urls(post: dict) -> list[str]:
    urls: list[str] = []
    seen: set[str] = set()
    for media in extract_media_entries(post):
        for key in (
            "media_url_https",
            "media_url",
            "imageUrl",
            "image_url",
            "thumbnailUrl",
            "thumbnail_url",
            "url",
        ):
            value = media.get(key)
            if not isinstance(value, str):
                continue
            candidate = value.strip()
            if not candidate or "t.co/" in candidate or "/status/" in candidate:
                continue
            if candidate not in seen:
                seen.add(candidate)
                urls.append(candidate)
            break
    return urls


def extract_video_url(post: dict) -> str | None:
    direct = post.get("videoUrl") or post.get("video_url")
    if isinstance(direct, str) and direct.strip():
        return direct.strip()

    for media in extract_media_entries(post):
        for key in ("videoUrl", "video_url", "playbackUrl", "playback_url", "contentUrl", "content_url"):
            value = media.get(key)
            if isinstance(value, str) and value.strip():
                return value.strip()
    return None


def fetch_user_posts(username: str, limit: int) -> tuple[list[dict], str | None]:
    env = {**os.environ}
    if TWITTER_AUTH_TOKEN:
        env["TWITTER_AUTH_TOKEN"] = TWITTER_AUTH_TOKEN
    if TWITTER_CT0:
        env["TWITTER_CT0"] = TWITTER_CT0
    if HTTP_PROXY:
        env["HTTP_PROXY"] = HTTP_PROXY
    if HTTPS_PROXY:
        env["HTTPS_PROXY"] = HTTPS_PROXY

    try:
        result = subprocess.run(
            [TWITTER_BIN, "user-posts", f"@{username}", "-n", str(limit), "--json"],
            capture_output=True,
            text=True,
            env=env,
            timeout=REQUEST_TIMEOUT_SECONDS,
        )
    except FileNotFoundError:
        return [], f"twitter binary not found: {TWITTER_BIN}"
    except subprocess.TimeoutExpired:
        return [], f"twitter-cli timed out for @{username}"

    if result.returncode != 0:
        error = (result.stderr or result.stdout or "twitter-cli failed").strip()
        return [], error[:400]

    try:
        parsed = json.loads(result.stdout)
    except Exception as exc:
        return [], f"twitter-cli returned invalid json: {exc}"

    if not parsed or not parsed.get("ok"):
        error = parsed.get("error", {}) if isinstance(parsed, dict) else {}
        message = error.get("message") if isinstance(error, dict) else None
        return [], str(message or "unknown twitter-cli error")

    data = parsed.get("data")
    if not isinstance(data, list):
        return [], "twitter-cli response missing data array"

    return [item for item in data if isinstance(item, dict)], None


def normalize_post(post: dict, username: str, persona_id: str) -> dict | None:
    if is_retweet(post):
        return None

    post_id = str(post.get("id", "")).strip()
    text = str(post.get("text") or post.get("fullText") or post.get("full_text") or "").strip()
    created_iso = str(post.get("createdAtISO") or post.get("createdAt") or "").strip()

    if not post_id or not text or not created_iso:
        return None

    if len(normalize_content_for_quality_check(text)) < 12 and not extract_media_urls(post) and not extract_video_url(post):
        return None

    dt = parse_dt(created_iso)
    if dt is None:
        return None

    return {
        "id": post_id,
        "personaId": persona_id,
        "content": text,
        "sourceType": "x",
        "sourceUrl": f"https://x.com/{username}/status/{post_id}",
        "topic": None,
        "importanceScore": compute_importance(post),
        "mediaUrls": extract_media_urls(post),
        "videoUrl": extract_video_url(post),
        "publishedAt": dt.astimezone(timezone.utc).isoformat(),
        "rawAuthorUsername": username,
        "rawPayload": post,
    }


class Handler(BaseHTTPRequestHandler):
    server_version = "BruhXScrape/1.0"

    def log_message(self, fmt: str, *args) -> None:
        sys.stdout.write("%s - - [%s] %s\n" % (
            self.client_address[0],
            self.log_date_time_string(),
            fmt % args,
        ))

    def _write_json(self, status: int, payload: dict) -> None:
        encoded = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(encoded)))
        self.end_headers()
        self.wfile.write(encoded)

    def _authorized(self) -> bool:
        if not SERVICE_TOKEN:
            return True
        header = self.headers.get("Authorization", "")
        return header == f"Bearer {SERVICE_TOKEN}"

    def do_GET(self) -> None:
        if self.path.rstrip("/") == "/health":
            self._write_json(
                200,
                {
                    "ok": True,
                    "service": "x_scrape_service",
                    "appEnv": APP_ENV,
                    "twitterBin": TWITTER_BIN,
                    "personaCount": len(PERSONA_MAP),
                },
            )
            return

        self._write_json(404, {"error": "not_found"})

    def do_POST(self) -> None:
        if self.path.rstrip("/") != "/fetch":
            self._write_json(404, {"error": "not_found"})
            return

        if not self._authorized():
            self._write_json(401, {"error": "unauthorized"})
            return

        try:
            content_length = int(self.headers.get("Content-Length", "0"))
        except ValueError:
            content_length = 0

        raw = self.rfile.read(content_length) if content_length > 0 else b"{}"
        try:
            payload = json.loads(raw.decode("utf-8"))
        except json.JSONDecodeError:
            self._write_json(400, {"error": "invalid_json"})
            return

        requested_usernames = payload.get("usernames") if isinstance(payload, dict) else None
        if isinstance(requested_usernames, list):
            usernames = [
                username
                for username in (normalize_username(str(item)) for item in requested_usernames)
                if username in PERSONA_MAP
            ]
        else:
            usernames = sorted(PERSONA_MAP.keys())

        usernames = list(dict.fromkeys(usernames))
        limit_per_user = payload.get("limitPerUser", DEFAULT_LIMIT_PER_USER) if isinstance(payload, dict) else DEFAULT_LIMIT_PER_USER
        try:
            limit_per_user = int(limit_per_user)
        except (TypeError, ValueError):
            limit_per_user = DEFAULT_LIMIT_PER_USER
        limit_per_user = max(1, min(limit_per_user, 50))

        if not usernames:
            self._write_json(
                200,
                {
                    "ok": True,
                    "provider": "self_hosted:twitter_cli",
                    "matchedAttempt": "twitter_cli",
                    "summaries": [{
                        "name": "twitter_cli",
                        "status": "SKIPPED",
                        "statusMessage": "no_supported_usernames",
                        "itemCount": 0,
                    }],
                    "posts": [],
                    "blockedReason": None,
                },
            )
            return

        normalized_posts: list[dict] = []
        failures: list[str] = []

        for username in usernames:
            persona_id = PERSONA_MAP.get(username)
            if not persona_id:
                continue

            posts, error = fetch_user_posts(username, limit_per_user)
            if error:
                failures.append(f"@{username}: {error}")
                continue

            for post in posts:
                normalized = normalize_post(post, username, persona_id)
                if normalized is not None:
                    normalized_posts.append(normalized)

        status = "SUCCEEDED"
        if failures and normalized_posts:
            status = "PARTIAL"
        elif failures and not normalized_posts:
            status = "REQUEST_FAILED"

        blocked_reason = "; ".join(failures) if failures and not normalized_posts else None
        status_message = "; ".join(failures) if failures else None

        self._write_json(
            200 if status != "REQUEST_FAILED" else 502,
            {
                "ok": status != "REQUEST_FAILED",
                "provider": "self_hosted:twitter_cli",
                "matchedAttempt": "twitter_cli" if normalized_posts else None,
                "summaries": [{
                    "name": "twitter_cli",
                    "status": status,
                    "statusMessage": status_message,
                    "itemCount": len(normalized_posts),
                }],
                "posts": normalized_posts,
                "blockedReason": blocked_reason,
                "usernames": usernames,
                "failures": failures,
            },
        )


def main() -> None:
    server = ThreadingHTTPServer((SERVICE_HOST, SERVICE_PORT), Handler)
    print(
        f"Starting x_scrape_service on {SERVICE_HOST}:{SERVICE_PORT} "
        f"(env={APP_ENV}, twitter_bin={TWITTER_BIN})"
    )
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
