import { corsHeaders } from "../_shared/cors.ts"
import { normalizeAssetUrl } from "../_shared/media.ts"
import {
  inferContentTypeFromKey,
  mirrorAssetToCache,
  resolveCachedMediaPath,
} from "../_shared/media_cache.ts"
import { shouldProxyAssetUrl } from "../_shared/media_proxy.ts"

const port = Number(Deno.env.get("PORT") ?? "8000")

function copyHeaderIfPresent(source: Headers, target: Headers, key: string) {
  const value = source.get(key)
  if (value) target.set(key, value)
}

function extractKeyFromMirroredUrl(value: string | null) {
  if (!value) return null
  try {
    const url = new URL(value)
    const key = url.searchParams.get("key")
    return key?.trim() || null
  } catch {
    return null
  }
}

function parseByteRange(headerValue: string | null, totalSize: number) {
  if (!headerValue?.startsWith("bytes=")) return null
  const rawRange = headerValue.slice("bytes=".length).split(",", 1)[0]?.trim()
  if (!rawRange) return null

  const [startRaw, endRaw] = rawRange.split("-", 2)
  if (startRaw === "" && endRaw === "") return null

  let start: number
  let end: number

  if (startRaw === "") {
    const suffixLength = Number.parseInt(endRaw, 10)
    if (!Number.isFinite(suffixLength) || suffixLength <= 0) return null
    start = Math.max(totalSize - suffixLength, 0)
    end = totalSize - 1
  } else {
    start = Number.parseInt(startRaw, 10)
    if (!Number.isFinite(start) || start < 0) return null
    end = endRaw === ""
      ? totalSize - 1
      : Number.parseInt(endRaw, 10)
    if (!Number.isFinite(end) || end < start) return null
    end = Math.min(end, totalSize - 1)
  }

  if (start >= totalSize) return null
  return { start, end }
}

async function respondWithCachedFile(
  request: Request,
  cacheKey: string,
  cachedPath: string,
) {
  const fileInfo = await Deno.stat(cachedPath)
  const totalSize = fileInfo.size
  const responseHeaders = new Headers(corsHeaders)
  responseHeaders.set("accept-ranges", "bytes")
  responseHeaders.set("cache-control", "public, max-age=31536000, immutable")
  responseHeaders.set("content-type", inferContentTypeFromKey(cacheKey))

  const byteRange = parseByteRange(request.headers.get("range"), totalSize)
  if (byteRange) {
    const bytes = await Deno.readFile(cachedPath)
    const body = bytes.slice(byteRange.start, byteRange.end + 1)
    responseHeaders.set("content-length", String(body.byteLength))
    responseHeaders.set("content-range", `bytes ${byteRange.start}-${byteRange.end}/${totalSize}`)
    return new Response(
      request.method === "HEAD" ? null : body,
      { status: 206, headers: responseHeaders },
    )
  }

  responseHeaders.set("content-length", String(totalSize))
  const body = request.method === "HEAD" ? null : await Deno.readFile(cachedPath)
  return new Response(body, {
    status: 200,
    headers: responseHeaders,
  })
}

Deno.serve({ port }, async (request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders })
  }

  if (request.method !== "GET" && request.method !== "HEAD") {
    return Response.json(
      { error: "Method not allowed", errorCategory: "validation" },
      { status: 405, headers: corsHeaders },
    )
  }

  const requestUrl = new URL(request.url)
  const cacheKey = requestUrl.searchParams.get("key")?.trim() || null
  if (cacheKey) {
    const cachedPath = await resolveCachedMediaPath(cacheKey)
    if (!cachedPath) {
      return Response.json(
        { error: "Cached media not found", errorCategory: "not_found" },
        { status: 404, headers: corsHeaders },
      )
    }
    return await respondWithCachedFile(request, cacheKey, cachedPath)
  }

  const upstreamUrl = normalizeAssetUrl(requestUrl.searchParams.get("url"))
  if (!upstreamUrl || !shouldProxyAssetUrl(upstreamUrl)) {
    return Response.json(
      { error: "Unsupported media URL", errorCategory: "validation" },
      { status: 400, headers: corsHeaders },
    )
  }

  try {
    const mirroredUrl = await mirrorAssetToCache(upstreamUrl)
    const mirroredKey = extractKeyFromMirroredUrl(mirroredUrl)
    const cachedPath = mirroredKey ? await resolveCachedMediaPath(mirroredKey) : null
    if (mirroredKey && cachedPath) {
      return await respondWithCachedFile(request, mirroredKey, cachedPath)
    }
  } catch {
    // fall through to direct upstream proxy below
  }

  let upstreamResponse: Response
  try {
    const upstreamHeaders = new Headers()
    copyHeaderIfPresent(request.headers, upstreamHeaders, "accept")
    copyHeaderIfPresent(request.headers, upstreamHeaders, "if-none-match")
    copyHeaderIfPresent(request.headers, upstreamHeaders, "if-modified-since")
    copyHeaderIfPresent(request.headers, upstreamHeaders, "range")
    upstreamHeaders.set(
      "user-agent",
      "Mozilla/5.0 (compatible; BruhMediaProxy/1.0; +https://actionandlink.com.cn/archui/)",
    )

    upstreamResponse = await fetch(upstreamUrl, {
      method: request.method,
      headers: upstreamHeaders,
      redirect: "follow",
    })
  } catch (error) {
    return Response.json(
      {
        error: error instanceof Error ? error.message : "Upstream media fetch failed",
        errorCategory: "network",
      },
      { status: 502, headers: corsHeaders },
    )
  }

  const responseHeaders = new Headers(corsHeaders)
  for (const key of [
    "accept-ranges",
    "cache-control",
    "content-length",
    "content-range",
    "content-type",
    "etag",
    "expires",
    "last-modified",
  ]) {
    copyHeaderIfPresent(upstreamResponse.headers, responseHeaders, key)
  }
  if (!responseHeaders.has("cache-control")) {
    responseHeaders.set("cache-control", "public, max-age=3600")
  }

  return new Response(
    request.method === "HEAD" ? null : upstreamResponse.body,
    {
      status: upstreamResponse.status,
      headers: responseHeaders,
    },
  )
})
