import { corsHeaders } from "../_shared/cors.ts"
import { normalizeAssetUrl } from "../_shared/media.ts"
import { shouldProxyAssetUrl } from "../_shared/media_proxy.ts"

const port = Number(Deno.env.get("PORT") ?? "8000")

function copyHeaderIfPresent(source: Headers, target: Headers, key: string) {
  const value = source.get(key)
  if (value) target.set(key, value)
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
  const upstreamUrl = normalizeAssetUrl(requestUrl.searchParams.get("url"))
  if (!upstreamUrl || !shouldProxyAssetUrl(upstreamUrl)) {
    return Response.json(
      { error: "Unsupported media URL", errorCategory: "validation" },
      { status: 400, headers: corsHeaders },
    )
  }

  const upstreamHeaders = new Headers()
  copyHeaderIfPresent(request.headers, upstreamHeaders, "accept")
  copyHeaderIfPresent(request.headers, upstreamHeaders, "if-none-match")
  copyHeaderIfPresent(request.headers, upstreamHeaders, "if-modified-since")
  copyHeaderIfPresent(request.headers, upstreamHeaders, "range")
  upstreamHeaders.set(
    "user-agent",
    "Mozilla/5.0 (compatible; BruhMediaProxy/1.0; +https://actionandlink.com.cn/archui/)",
  )

  let upstreamResponse: Response
  try {
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
