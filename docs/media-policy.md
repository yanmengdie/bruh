# Media Policy

## Goal

Unify the baseline rules for image, video, audio, and source links without changing UI layout or interaction design.

## URL Rules

Backend and iOS now apply the same basic policy:

- source/article links allow `http` and `https`
- image, video, and audio asset links require `https`
- URL fragments are stripped
- loopback and private-network hosts are rejected
- duplicate media URLs are removed
- image collections are capped at `9`

This means invalid or unsafe media URLs are dropped before they reach the UI. The fallback behavior is intentional:

- invalid image URL -> keep text, omit image
- invalid video URL -> keep post/message, omit video
- invalid audio URL -> keep text reply, surface the existing audio error if any
- invalid source URL -> keep content, omit deep link

## Current Client Behavior

- feed and message DTO decoding now normalizes remote media fields before persistence
- feed/message views normalize any stored media strings again before rendering, which protects older local data
- voice playback caches downloaded audio in `Caches/VoiceMessages`
- if cached audio looks invalid, the client deletes it and retries one fresh download before surfacing an error
- images and videos remain remote-first; when loading fails, the current placeholder UI remains unchanged

## Current Backend Coverage

- `ingest-top-news`
  normalizes article URLs before `news_articles` upsert
- `ingest-x-posts`
  normalizes source/media/video URLs before `source_posts` upsert
- `build-feed` and `feed`
  normalize feed link and media fields before projection/response
- `generate-message`
  validates generated image/audio/source URLs before returning them
- `message-starters`
  validates generated image URLs and starter source links before returning them

## Known Limits

- image/video assets are not yet re-hosted or mirrored, so upstream expiration still causes graceful omission rather than automatic recovery
- voice cache cleanup is not yet time-based; the current baseline only guarantees invalid-cache eviction and fresh redownload on failure
- media MIME probing is still lightweight and focused on audio playback only
