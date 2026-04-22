import { getOptionalScopedEnv } from "./environment.ts"
import { normalizeAssetUrl } from "./media.ts"
import { shouldProxyAssetUrl } from "./media_proxy.ts"

const defaultMediaCacheDir = "/opt/bruh-selfhost/runtime/media-cache"
const defaultMaxMirrorBytes = 50 * 1024 * 1024

type EnvReader = {
  get(key: string): string | undefined
}

function normalizeExtension(value: string | null | undefined) {
  const trimmed = (value ?? "").trim().toLowerCase().replace(/^\./, "")
  if (!trimmed) return null

  switch (trimmed) {
    case "jpeg":
      return "jpg"
    case "quicktime":
      return "mov"
    default:
      return trimmed
  }
}

function extensionFromUrl(url: URL) {
  const match = url.pathname.toLowerCase().match(/\.([a-z0-9]{2,6})$/)
  return normalizeExtension(match?.[1] ?? null)
}

function extensionFromQuery(url: URL) {
  return normalizeExtension(
    url.searchParams.get("format") ??
      url.searchParams.get("fm") ??
      url.searchParams.get("ext"),
  )
}

function extensionFromContentType(value: string | null) {
  if (!value) return null
  const normalized = value.split(";")[0]?.trim().toLowerCase()
  switch (normalized) {
    case "image/jpeg":
      return "jpg"
    case "image/png":
      return "png"
    case "image/webp":
      return "webp"
    case "image/gif":
      return "gif"
    case "video/mp4":
      return "mp4"
    case "video/quicktime":
      return "mov"
    case "audio/mpeg":
      return "mp3"
    case "audio/mp4":
    case "audio/x-m4a":
      return "m4a"
    default:
      if (!normalized?.includes("/")) return null
      return normalizeExtension(normalized.split("/")[1] ?? null)
  }
}

async function sha256Hex(value: string) {
  const bytes = new TextEncoder().encode(value)
  const digest = await crypto.subtle.digest("SHA-256", bytes)
  return Array.from(new Uint8Array(digest)).map((item) =>
    item.toString(16).padStart(2, "0")
  ).join("")
}

async function ensureDirectory(path: string) {
  await Deno.mkdir(path, { recursive: true })
}

async function pathExists(path: string) {
  try {
    await Deno.stat(path)
    return true
  } catch (error) {
    if (error instanceof Deno.errors.NotFound) return false
    throw error
  }
}

async function readResponseBytes(response: Response, maxBytes: number) {
  const reader = response.body?.getReader()
  if (!reader) return new Uint8Array()

  const chunks: Uint8Array[] = []
  let total = 0

  while (true) {
    const { done, value } = await reader.read()
    if (done) break
    if (!value) continue
    total += value.byteLength
    if (total > maxBytes) {
      throw new Error(`Media asset exceeds configured max size of ${maxBytes} bytes.`)
    }
    chunks.push(value)
  }

  const output = new Uint8Array(total)
  let offset = 0
  for (const chunk of chunks) {
    output.set(chunk, offset)
    offset += chunk.byteLength
  }
  return output
}

function parseMaxBytes(env: EnvReader) {
  const raw = getOptionalScopedEnv("BRUH_MEDIA_CACHE_MAX_BYTES", { env })
  if (!raw) return defaultMaxMirrorBytes
  const parsed = Number.parseInt(raw, 10)
  if (!Number.isFinite(parsed) || parsed <= 0) return defaultMaxMirrorBytes
  return parsed
}

export function resolveMediaCacheDir(env: EnvReader = Deno.env) {
  return getOptionalScopedEnv("BRUH_MEDIA_CACHE_DIR", { env })?.trim() || defaultMediaCacheDir
}

export function resolveMediaMirrorFunctionsBaseUrl(env: EnvReader = Deno.env) {
  return getOptionalScopedEnv("BRUH_FUNCTIONS_BASE_URL", {
    env,
    aliases: ["SUPABASE_FUNCTIONS_BASE_URL"],
  })?.trim().replace(/\/+$/, "") || null
}

export function buildMirroredProxyUrl(cacheKey: string, env: EnvReader = Deno.env) {
  const functionsBaseUrl = resolveMediaMirrorFunctionsBaseUrl(env)
  if (!functionsBaseUrl) return null

  const url = new URL(`${functionsBaseUrl}/media-proxy`)
  url.searchParams.set("key", cacheKey)
  return url.toString()
}

export function inferContentTypeFromKey(cacheKey: string) {
  const extension = normalizeExtension(cacheKey.split(".").pop() ?? null)
  switch (extension) {
    case "jpg":
      return "image/jpeg"
    case "png":
      return "image/png"
    case "webp":
      return "image/webp"
    case "gif":
      return "image/gif"
    case "mp4":
      return "video/mp4"
    case "mov":
      return "video/quicktime"
    case "mp3":
      return "audio/mpeg"
    case "m4a":
      return "audio/mp4"
    default:
      return "application/octet-stream"
  }
}

export async function buildCacheKeyForAssetUrl(value: unknown, extensionHint?: string | null) {
  const normalized = normalizeAssetUrl(value)
  if (!normalized) return null

  const parsed = new URL(normalized)
  const extension = normalizeExtension(extensionHint) ||
    extensionFromUrl(parsed) ||
    extensionFromQuery(parsed) ||
    "bin"
  const digest = await sha256Hex(normalized)
  return `${digest}.${extension}`
}

export async function resolveCachedMediaPath(cacheKey: string, env: EnvReader = Deno.env) {
  if (!/^[a-f0-9]{64}\.[a-z0-9]{2,6}$/i.test(cacheKey)) {
    return null
  }

  const absolutePath = `${resolveMediaCacheDir(env).replace(/\/+$/, "")}/${cacheKey}`
  return await pathExists(absolutePath) ? absolutePath : null
}

export async function mirrorAssetToCache(value: unknown, env: EnvReader = Deno.env) {
  const normalized = normalizeAssetUrl(value)
  if (!normalized) return null
  if (!shouldProxyAssetUrl(normalized)) return normalized

  const initialKey = await buildCacheKeyForAssetUrl(normalized)
  if (!initialKey) return normalized

  const cachedUrl = buildMirroredProxyUrl(initialKey, env)
  if (!cachedUrl) return normalized

  const cacheDir = resolveMediaCacheDir(env)
  const initialPath = `${cacheDir.replace(/\/+$/, "")}/${initialKey}`
  if (await pathExists(initialPath)) {
    return cachedUrl
  }

  await ensureDirectory(cacheDir)

  const response = await fetch(normalized, {
    headers: {
      "user-agent": "Mozilla/5.0 (compatible; BruhMediaMirror/1.0)",
      "accept": "*/*",
    },
    redirect: "follow",
  })
  if (!response.ok) {
    return normalized
  }

  const maxBytes = parseMaxBytes(env)
  const contentLength = Number.parseInt(response.headers.get("content-length") ?? "", 10)
  if (Number.isFinite(contentLength) && contentLength > maxBytes) {
    return normalized
  }

  const bytes = await readResponseBytes(response, maxBytes)
  if (bytes.byteLength == 0) {
    return normalized
  }

  const extension = extensionFromContentType(response.headers.get("content-type")) ||
    normalizeExtension(initialKey.split(".").pop() ?? null) ||
    "bin"
  const finalKey = await buildCacheKeyForAssetUrl(normalized, extension)
  if (!finalKey) return normalized

  const finalPath = `${cacheDir.replace(/\/+$/, "")}/${finalKey}`
  if (!(await pathExists(finalPath))) {
    const tempPath = `${finalPath}.tmp-${crypto.randomUUID()}`
    await Deno.writeFile(tempPath, bytes)
    try {
      await Deno.rename(tempPath, finalPath)
    } catch (error) {
      if (error instanceof Deno.errors.AlreadyExists) {
        await Deno.remove(tempPath).catch(() => undefined)
      } else {
        throw error
      }
    }
  }

  return buildMirroredProxyUrl(finalKey, env) ?? normalized
}

export async function mirrorMediaUrls(value: unknown, limit = 9, env: EnvReader = Deno.env) {
  if (!Array.isArray(value)) return []

  const results: string[] = []
  const seen = new Set<string>()

  for (const item of value) {
    const mirrored = await mirrorAssetToCache(item, env)
    const normalized = normalizeAssetUrl(mirrored)
    if (!normalized || seen.has(normalized)) continue
    seen.add(normalized)
    results.push(normalized)
    if (results.length >= limit) break
  }

  return results
}

export async function mirrorVideoUrl(value: unknown, env: EnvReader = Deno.env) {
  return await mirrorAssetToCache(value, env)
}
