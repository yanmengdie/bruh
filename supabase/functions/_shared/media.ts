type NormalizeUrlOptions = {
  allowHttp?: boolean
}

const trustedAssetHttpUpgradeHostSuffixes = [
  "video.weibocdn.com",
]

function shouldUpgradeAssetHttpHost(hostname: string) {
  const normalized = hostname.trim().toLowerCase().replace(/^\[|\]$/g, "")
  if (!normalized) return false

  return trustedAssetHttpUpgradeHostSuffixes.some((suffix) =>
    normalized === suffix || normalized.endsWith(`.${suffix}`)
  )
}

function isLoopbackOrPrivateHost(hostname: string) {
  const normalized = hostname.trim().toLowerCase().replace(/^\[|\]$/g, "")
  if (!normalized) return true

  if (
    normalized === "localhost" ||
    normalized === "::1" ||
    normalized === "0.0.0.0" ||
    normalized.endsWith(".local") ||
    normalized.endsWith(".internal")
  ) {
    return true
  }

  const ipv4Match = normalized.match(/^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$/)
  if (!ipv4Match) {
    return false
  }

  const octets = ipv4Match.slice(1).map((item) => Number.parseInt(item, 10))
  if (octets.some((item) => Number.isNaN(item) || item < 0 || item > 255)) {
    return true
  }

  return (
    octets[0] === 0 ||
    octets[0] === 10 ||
    octets[0] === 127 ||
    (octets[0] === 169 && octets[1] === 254) ||
    (octets[0] === 172 && octets[1] >= 16 && octets[1] <= 31) ||
    (octets[0] === 192 && octets[1] === 168)
  )
}

function normalizeRemoteUrl(value: unknown, options: NormalizeUrlOptions = {}) {
  if (typeof value !== "string") return null

  const trimmed = value.trim()
  if (!trimmed) return null

  let parsed: URL
  try {
    parsed = new URL(trimmed)
  } catch {
    return null
  }

  const protocol = parsed.protocol.toLowerCase()
  if (protocol === "https:") {
    // allowed
  } else if (protocol === "http:" && options.allowHttp === true) {
    // allowed
  } else if (protocol === "http:" && shouldUpgradeAssetHttpHost(parsed.hostname)) {
    parsed.protocol = "https:"
    if (parsed.port === "80") {
      parsed.port = ""
    }
  } else {
    return null
  }

  if (parsed.username || parsed.password) {
    return null
  }

  if (isLoopbackOrPrivateHost(parsed.hostname)) {
    return null
  }

  parsed.hash = ""
  return parsed.toString()
}

export function normalizeSourceUrl(value: unknown) {
  return normalizeRemoteUrl(value, { allowHttp: true })
}

export function normalizeAssetUrl(value: unknown) {
  return normalizeRemoteUrl(value, { allowHttp: false })
}

export function normalizeMediaUrls(value: unknown, limit = 9) {
  if (!Array.isArray(value)) return []

  const results: string[] = []
  const seen = new Set<string>()

  for (const item of value) {
    const normalized = normalizeAssetUrl(item)
    if (!normalized) continue
    if (normalized.includes("://t.co/")) continue
    if (seen.has(normalized)) continue
    seen.add(normalized)
    results.push(normalized)
    if (results.length >= limit) break
  }

  return results
}

export function extractNormalizedVideoUrl(value: unknown): string | null {
  if (!value || typeof value !== "object") {
    return normalizeAssetUrl(value)
  }

  const record = value as Record<string, unknown>
  const sourcePosts = record.source_posts && typeof record.source_posts === "object"
    ? record.source_posts as Record<string, unknown>
    : null
  const rawPayload = record.raw_payload && typeof record.raw_payload === "object"
    ? record.raw_payload as Record<string, unknown>
    : null
  const sourcePostPayload = sourcePosts?.raw_payload && typeof sourcePosts.raw_payload === "object"
    ? sourcePosts.raw_payload as Record<string, unknown>
    : null
  const rawPayloadNote = rawPayload?.note && typeof rawPayload.note === "object"
    ? rawPayload.note as Record<string, unknown>
    : null
  const sourcePostPayloadNote = sourcePostPayload?.note && typeof sourcePostPayload.note === "object"
    ? sourcePostPayload.note as Record<string, unknown>
    : null

  const candidates = [
    record.video_url,
    record.videoUrl,
    sourcePosts?.video_url,
    sourcePosts?.videoUrl,
    rawPayload?.videoUrl,
    rawPayload?.video_url,
    rawPayloadNote?.videoUrl,
    rawPayloadNote?.video_url,
    sourcePostPayload?.videoUrl,
    sourcePostPayload?.video_url,
    sourcePostPayloadNote?.videoUrl,
    sourcePostPayloadNote?.video_url,
  ]

  for (const candidate of candidates) {
    const normalized = normalizeAssetUrl(candidate)
    if (normalized) return normalized
  }

  return null
}
