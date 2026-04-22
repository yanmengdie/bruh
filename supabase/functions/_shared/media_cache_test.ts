import {
  buildCacheKeyForAssetUrl,
  buildMirroredProxyUrl,
  inferContentTypeFromKey,
} from "./media_cache.ts"

Deno.test("buildCacheKeyForAssetUrl is deterministic and preserves extension", async () => {
  const key = await buildCacheKeyForAssetUrl(
    "https://pbs.twimg.com/media/example.jpg?format=jpg&name=large",
  )
  if (!key || !/^[a-f0-9]{64}\.jpg$/.test(key)) {
    throw new Error(`unexpected cache key: ${key ?? "null"}`)
  }
})

Deno.test("buildCacheKeyForAssetUrl reads extension from query parameters", async () => {
  const key = await buildCacheKeyForAssetUrl(
    "https://pbs.twimg.com/media/example?format=png&name=large",
  )
  if (!key || !/^[a-f0-9]{64}\.png$/.test(key)) {
    throw new Error(`unexpected cache key from query params: ${key ?? "null"}`)
  }
})

Deno.test("buildMirroredProxyUrl uses configured functions gateway", () => {
  const env = {
    get(key: string) {
      if (key === "BRUH_FUNCTIONS_BASE_URL") {
        return "https://api.example.com/functions/v1"
      }
      return undefined
    },
  }

  const url = buildMirroredProxyUrl("abc123.jpg", env)
  if (url !== "https://api.example.com/functions/v1/media-proxy?key=abc123.jpg") {
    throw new Error(`unexpected mirrored proxy url: ${url ?? "null"}`)
  }
})

Deno.test("inferContentTypeFromKey resolves common media types", () => {
  if (inferContentTypeFromKey("abc.jpg") !== "image/jpeg") {
    throw new Error("expected jpg content type")
  }
  if (inferContentTypeFromKey("abc.mp4") !== "video/mp4") {
    throw new Error("expected mp4 content type")
  }
})
