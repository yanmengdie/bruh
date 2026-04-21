#!/usr/bin/env python3
"""
Fetch recent Weibo posts for personas with active weibo accounts and upsert them
to source_posts through PostgREST.

This path intentionally relies on a user-authorized cookie. It does not attempt
to bypass Weibo visitor or bot-detection systems.
"""

from __future__ import annotations

import html
import json
import os
import re
import sys
import urllib.error
import urllib.parse
import urllib.request
from dataclasses import dataclass
from datetime import datetime, timezone
from email.utils import parsedate_to_datetime
from pathlib import Path


ROOT_DIR = Path(__file__).resolve().parents[1]
PERSONA_FILE = ROOT_DIR / "bruh" / "SharedPersonas.json"
STATE_FILE = Path(os.path.expanduser("~/.bruh-weibo-ingest-state.json"))


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

WEIBO_COOKIE = resolve_env("WEIBO_COOKIE", required=True)
WEIBO_USER_AGENT = resolve_env(
    "WEIBO_USER_AGENT",
    default=(
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
        "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36"
    ),
) or ""
REQUEST_TIMEOUT_SECONDS = int(resolve_env("WEIBO_REQUEST_TIMEOUT_SECONDS", default="20") or "20")
FETCH_LIMIT = int(resolve_env("WEIBO_FETCH_LIMIT", default="10") or "10")


def extract_xsrf_token(cookie: str) -> str | None:
    match = re.search(r"(?:^|;\s*)(?:XSRF-TOKEN|XSRF_TOKEN)=([^;]+)", cookie)
    if not match:
        return None
    return urllib.parse.unquote(match.group(1))


WEIBO_XSRF_TOKEN = extract_xsrf_token(WEIBO_COOKIE)


@dataclass(frozen=True)
class PersonaAccount:
    persona_id: str
    display_name: str
    handle: str
    profile_url: str


def load_state() -> dict[str, str]:
    try:
        return json.loads(STATE_FILE.read_text(encoding="utf-8"))
    except (FileNotFoundError, json.JSONDecodeError):
        return {}


def save_state(state: dict[str, str]) -> None:
    STATE_FILE.write_text(json.dumps(state, ensure_ascii=False, indent=2), encoding="utf-8")


def build_headers(*, accept_json: bool, referer: str | None = None) -> dict[str, str]:
    headers = {
        "Accept": "application/json, text/plain, */*" if accept_json else "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
        "Cookie": WEIBO_COOKIE,
        "User-Agent": WEIBO_USER_AGENT,
    }
    if referer:
        headers["Referer"] = referer
    if WEIBO_XSRF_TOKEN:
        headers["x-xsrf-token"] = WEIBO_XSRF_TOKEN
    return headers


def http_get_json(url: str, *, referer: str | None = None) -> dict:
    request = urllib.request.Request(url, headers=build_headers(accept_json=True, referer=referer))
    with urllib.request.urlopen(request, timeout=REQUEST_TIMEOUT_SECONDS) as response:
        payload = response.read().decode("utf-8")
    return json.loads(payload)


def load_persona_accounts() -> list[PersonaAccount]:
    try:
        payload = json.loads(PERSONA_FILE.read_text(encoding="utf-8"))
    except FileNotFoundError as exc:
        raise RuntimeError(f"Missing persona file: {PERSONA_FILE}") from exc

    accounts: list[PersonaAccount] = []
    for record in payload:
        persona_id = str(record.get("id", "")).strip()
        display_name = str(record.get("displayName", "")).strip()
        if not persona_id:
            continue

        for account in record.get("platformAccounts", []):
            if not isinstance(account, dict):
                continue
            if str(account.get("platform", "")).strip().lower() != "weibo":
                continue
            if account.get("isActive", True) is False:
                continue

            handle = str(account.get("handle", "")).strip().lstrip("@")
            profile_url = str(account.get("profileUrl", "")).strip() or f"https://weibo.com/{handle}"
            if handle:
                accounts.append(
                    PersonaAccount(
                        persona_id=persona_id,
                        display_name=display_name or persona_id,
                        handle=handle,
                        profile_url=profile_url,
                    )
                )
    return accounts


def resolve_uid(account: PersonaAccount) -> str:
    if account.handle.isdigit():
        return account.handle

    candidates = [account.handle]
    parsed = urllib.parse.urlparse(account.profile_url)
    slug = parsed.path.strip("/").split("/", 1)[0]
    if slug and slug not in candidates:
        candidates.append(slug)

    for candidate in candidates:
        url = f"https://weibo.com/ajax/profile/info?custom={urllib.parse.quote(candidate)}"
        try:
            payload = http_get_json(url, referer=account.profile_url)
        except urllib.error.HTTPError as exc:
            if exc.code in {401, 403, 414, 418, 432}:
                continue
            raise

        user = payload.get("data", {}).get("user", {}) if isinstance(payload.get("data"), dict) else {}
        uid = str(user.get("idstr") or user.get("id") or "").strip()
        if uid:
            return uid

    raise RuntimeError(f"Unable to resolve Weibo uid for @{account.handle}. Refresh WEIBO_COOKIE or verify the profile URL.")


def parse_published_at(value: str) -> datetime | None:
    text = value.strip()
    if not text:
        return None

    try:
        parsed = parsedate_to_datetime(text)
        if parsed.tzinfo is None:
            parsed = parsed.replace(tzinfo=timezone.utc)
        return parsed.astimezone(timezone.utc)
    except (TypeError, ValueError, IndexError):
        return None


def strip_html_text(raw: str) -> str:
    text = re.sub(r"<br\s*/?>", "\n", raw, flags=re.IGNORECASE)
    text = re.sub(r"<[^>]+>", " ", text)
    text = html.unescape(text)
    text = re.sub(r"\s+", " ", text).strip()
    return text


def is_low_quality(text: str) -> bool:
    normalized = re.sub(r"https?://\S+", " ", text)
    normalized = re.sub(r"@\S+", " ", normalized)
    normalized = re.sub(r"\s+", " ", normalized).strip()
    return len(normalized) < 12


def extract_media_urls(status: dict) -> list[str]:
    urls: list[str] = []
    seen: set[str] = set()

    def add_url(value: object) -> None:
        if not isinstance(value, str):
            return
        candidate = value.strip()
        if not candidate or candidate in seen:
            return
        seen.add(candidate)
        urls.append(candidate)

    def preferred_pic_info_url(info: dict) -> str | None:
        for key in ("largest", "large", "original", "mw2000", "bmiddle", "thumbnail"):
            variant = info.get(key)
            if not isinstance(variant, dict):
                continue
            url = variant.get("url")
            if isinstance(url, str) and url.strip():
                return url.strip()
        return None

    for pic in status.get("pics", []) if isinstance(status.get("pics"), list) else []:
        if not isinstance(pic, dict):
            continue
        add_url(pic.get("large", {}).get("url") if isinstance(pic.get("large"), dict) else None)
        add_url(pic.get("url"))

    pic_infos = status.get("pic_infos") if isinstance(status.get("pic_infos"), dict) else {}
    ordered_pic_ids = status.get("pic_ids") if isinstance(status.get("pic_ids"), list) else []
    for pic_id in ordered_pic_ids:
        if not isinstance(pic_id, str):
            continue
        info = pic_infos.get(pic_id)
        if not isinstance(info, dict):
            continue
        add_url(preferred_pic_info_url(info))

    for info in pic_infos.values():
        if not isinstance(info, dict):
            continue
        add_url(preferred_pic_info_url(info))

    page_info = status.get("page_info") if isinstance(status.get("page_info"), dict) else {}
    page_pic = page_info.get("page_pic") if isinstance(page_info.get("page_pic"), dict) else {}
    add_url(page_pic.get("url"))

    mix_media = status.get("mix_media_info") if isinstance(status.get("mix_media_info"), dict) else {}
    for item in mix_media.get("items", []) if isinstance(mix_media.get("items"), list) else []:
        if not isinstance(item, dict):
            continue
        data = item.get("data") if isinstance(item.get("data"), dict) else {}
        largest = data.get("largest") if isinstance(data.get("largest"), dict) else {}
        large = data.get("large") if isinstance(data.get("large"), dict) else {}
        add_url(largest.get("url"))
        add_url(large.get("url"))

    return urls


def extract_video_url(status: dict) -> str | None:
    page_info = status.get("page_info") if isinstance(status.get("page_info"), dict) else {}
    media_info = page_info.get("media_info") if isinstance(page_info.get("media_info"), dict) else {}
    for key in ("stream_url_hd", "stream_url", "mp4_hd_url", "mp4_sd_url"):
        value = media_info.get(key)
        if isinstance(value, str) and value.strip():
            return value.strip()
    return None


def compute_importance(status: dict) -> float:
    attitudes = float(status.get("attitudes_count") or 0)
    comments = float(status.get("comments_count") or 0)
    reposts = float(status.get("reposts_count") or 0)
    raw = 0.5 + min((attitudes + comments * 1.5 + reposts * 2) / 1000.0, 0.49)
    return round(raw, 2)


def fetch_statuses(uid: str, account: PersonaAccount) -> list[dict]:
    url = (
        "https://weibo.com/ajax/statuses/mymblog?"
        + urllib.parse.urlencode(
            {
                "uid": uid,
                "page": 1,
                "feature": 0,
            }
        )
    )
    payload = http_get_json(url, referer=account.profile_url)
    data = payload.get("data") if isinstance(payload.get("data"), dict) else {}
    items = data.get("list")
    if not isinstance(items, list):
        return []
    return [item for item in items if isinstance(item, dict)]


def normalize_status(status: dict, *, account: PersonaAccount, uid: str) -> tuple[dict, datetime] | None:
    if status.get("retweeted_status"):
        return None

    post_id = str(status.get("idstr") or status.get("id") or "").strip()
    bid = str(status.get("bid") or "").strip()
    if not post_id:
        return None

    content = str(status.get("text_raw") or "").strip()
    if not content:
        content = strip_html_text(str(status.get("text") or ""))
    if not content or is_low_quality(content):
        return None

    published_at_raw = str(status.get("created_at") or "").strip()
    published_at = parse_published_at(published_at_raw)
    if published_at is None:
        return None

    media_urls = extract_media_urls(status)
    video_url = extract_video_url(status)
    source_suffix = bid or post_id
    source_url = f"https://weibo.com/{uid}/{source_suffix}"

    row = {
        "id": f"weibo:{post_id}",
        "persona_id": account.persona_id,
        "source_type": "weibo",
        "content": content,
        "source_url": source_url,
        "topic": None,
        "importance_score": compute_importance(status),
        "published_at": published_at.isoformat(),
        "raw_author_username": account.handle,
        "raw_payload": status,
        "media_urls": media_urls,
        "video_url": video_url,
    }
    return row, published_at


def supabase_upsert(rows: list[dict]) -> dict:
    if not SUPABASE_URL or not SUPABASE_SERVICE_ROLE_KEY:
        return {"ok": False, "status": 500, "error": "Missing Supabase environment variables"}

    payload = json.dumps(rows).encode()
    request = urllib.request.Request(
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
        with urllib.request.urlopen(request, timeout=15) as response:
            return {"ok": True, "status": response.status}
    except urllib.error.HTTPError as exc:
        body = exc.read().decode()
        return {"ok": False, "status": exc.code, "error": body}


def main() -> int:
    print(f"Environment: {APP_ENV}")
    if not SUPABASE_URL or not SUPABASE_SERVICE_ROLE_KEY:
        raise RuntimeError(
            "Missing Supabase configuration. Set SUPABASE_URL/PROJECT_URL and "
            "SUPABASE_SERVICE_ROLE_KEY/SERVICE_ROLE_KEY, optionally with environment suffixes."
        )

    accounts = load_persona_accounts()
    if not accounts:
        print("No active weibo persona accounts configured.")
        return 0

    state = load_state()
    next_state = dict(state)
    total_new = 0

    for account in accounts:
        state_key = f"{account.persona_id}:{account.handle}"
        last_seen_raw = state.get(state_key, "")
        last_seen = None
        if last_seen_raw:
            try:
                last_seen = datetime.fromisoformat(last_seen_raw.replace("Z", "+00:00"))
            except ValueError:
                last_seen = None

        print(f"\n-> {account.display_name} @{account.handle}")
        if last_seen:
            print(f"  last seen: {last_seen.astimezone(timezone.utc).strftime('%Y-%m-%d %H:%M UTC')}")
        else:
            print("  first run - no baseline yet")

        try:
            uid = resolve_uid(account)
            statuses = fetch_statuses(uid, account)
        except urllib.error.HTTPError as exc:
            print(f"  [error] HTTP {exc.code} while reading Weibo. Refresh WEIBO_COOKIE.", file=sys.stderr)
            continue
        except Exception as exc:
            print(f"  [error] {exc}", file=sys.stderr)
            continue

        print(f"  fetched: {len(statuses)}")
        normalized = [normalize_status(status, account=account, uid=uid) for status in statuses]
        valid = [(row, published_at) for item in normalized if item is not None for row, published_at in [item]]
        valid.sort(key=lambda item: item[1], reverse=True)

        if last_seen:
            fresh = [(row, published_at) for row, published_at in valid if published_at > last_seen]
            print(f"  newer than last run: {len(fresh)}  already seen: {len(valid) - len(fresh)}")
        else:
            fresh = valid[:FETCH_LIMIT]
            print(f"  normalized: {len(fresh)}  filtered: {len(statuses) - len(valid)}")

        if not fresh:
            print("  nothing new")
            if valid:
                next_state[state_key] = valid[0][1].isoformat()
            continue

        rows = [row for row, _ in fresh[:FETCH_LIMIT]]
        result = supabase_upsert(rows)
        if not result.get("ok"):
            print(
                f"  [error] upsert failed ({result.get('status')}): {result.get('error', 'unknown error')}",
                file=sys.stderr,
            )
            continue

        newest_seen = max(published_at for _, published_at in fresh[:FETCH_LIMIT])
        next_state[state_key] = newest_seen.isoformat()
        total_new += len(rows)
        print(f"  upserted: {len(rows)} rows ok")

    save_state(next_state)
    print(f"\nDone. New rows: {total_new}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
