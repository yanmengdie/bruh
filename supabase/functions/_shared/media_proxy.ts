import { getOptionalScopedEnv } from "./environment.ts"
import { normalizeAssetUrl, normalizeMediaUrls } from "./media.ts"

const proxiedAssetHostSuffixes = [
  "twimg.com",
]

function normalizeHostname(value: string) {
  return value.trim().toLowerCase().replace(/^\[|\]$/g, "")
}

function stripPort(value: string) {
  const trimmed = value.trim()
  if (!trimmed) return ""
  if (trimmed.startsWith("[")) {
    const closingIndex = trimmed.indexOf("]")
    return closingIndex === -1 ? trimmed : trimmed.slice(1, closingIndex)
  }
  const colonIndex = trimmed.indexOf(":")
  return colonIndex === -1 ? trimmed : trimmed.slice(0, colonIndex)
}

function isLoopbackOrPrivateHost(hostname: string) {
  const normalized = normalizeHostname(hostname)
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

function shouldProxyHostname(hostname: string) {
  const normalized = normalizeHostname(hostname)
  if (!normalized) return false

  return proxiedAssetHostSuffixes.some((suffix) =>
    normalized === suffix || normalized.endsWith(`.${suffix}`)
  )
}

export function shouldProxyAssetUrl(value: unknown) {
  const normalized = normalizeAssetUrl(value)
  if (!normalized) return false

  try {
    return shouldProxyHostname(new URL(normalized).hostname)
  } catch {
    return false
  }
}

export function resolvePublicFunctionsBaseUrl(
  request: Request,
  env: { get(key: string): string | undefined } = Deno.env,
) {
  const configured = getOptionalScopedEnv("BRUH_FUNCTIONS_BASE_URL", {
    env,
    aliases: ["SUPABASE_FUNCTIONS_BASE_URL"],
  })
  if (configured) {
    return configured.trim().replace(/\/+$/, "")
  }

  const forwardedHost = request.headers.get("x-forwarded-host")?.trim()
  if (forwardedHost) {
    const hostWithoutPort = stripPort(forwardedHost)
    if (!isLoopbackOrPrivateHost(hostWithoutPort)) {
      return `https://${forwardedHost}/functions/v1`
    }
  }

  const requestUrl = new URL(request.url)
  if (
    requestUrl.protocol === "https:" &&
    !isLoopbackOrPrivateHost(requestUrl.hostname)
  ) {
    return `${requestUrl.origin}/functions/v1`
  }

  return null
}

export function buildProxiedAssetUrl(value: unknown, request: Request) {
  return buildProxiedAssetUrlWithEnv(value, request, Deno.env)
}

export function buildProxiedAssetUrlWithEnv(
  value: unknown,
  request: Request,
  env: { get(key: string): string | undefined },
) {
  const normalized = normalizeAssetUrl(value)
  if (!normalized) return null
  if (!shouldProxyAssetUrl(normalized)) return normalized

  const functionsBaseUrl = resolvePublicFunctionsBaseUrl(request, env)
  if (!functionsBaseUrl) return normalized

  const proxiedUrl = new URL(`${functionsBaseUrl}/media-proxy`)
  proxiedUrl.searchParams.set("url", normalized)
  return proxiedUrl.toString()
}

export function buildProxiedMediaUrls(value: unknown, request: Request, limit = 9) {
  return buildProxiedMediaUrlsWithEnv(value, request, limit, Deno.env)
}

export function buildProxiedMediaUrlsWithEnv(
  value: unknown,
  request: Request,
  limit = 9,
  env: { get(key: string): string | undefined },
) {
  const results: string[] = []
  const seen = new Set<string>()

  for (const item of normalizeMediaUrls(value, limit)) {
    const proxied = buildProxiedAssetUrlWithEnv(item, request, env)
    if (!proxied || seen.has(proxied)) continue
    seen.add(proxied)
    results.push(proxied)
    if (results.length >= limit) break
  }

  return results
}
