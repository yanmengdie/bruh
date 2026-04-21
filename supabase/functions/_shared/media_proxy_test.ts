import {
  buildProxiedAssetUrlWithEnv,
  buildProxiedMediaUrlsWithEnv,
  resolvePublicFunctionsBaseUrl,
  shouldProxyAssetUrl,
} from "./media_proxy.ts"

Deno.test("resolvePublicFunctionsBaseUrl prefers configured functions base url", () => {
  const request = new Request("http://127.0.0.1:9001/feed")
  const env = {
    get(key: string) {
      if (key === "BRUH_FUNCTIONS_BASE_URL") {
        return "https://api.example.com/functions/v1"
      }
      return undefined
    },
  }

  const resolved = resolvePublicFunctionsBaseUrl(request, env)
  if (resolved !== "https://api.example.com/functions/v1") {
    throw new Error(`unexpected functions base url: ${resolved ?? "null"}`)
  }
})

Deno.test("buildProxiedAssetUrl rewrites twimg assets to the functions gateway", () => {
  const request = new Request("http://127.0.0.1:9001/feed", {
    headers: {
      "x-forwarded-host": "media.example.com",
    },
  })
  const env = { get: (_key: string) => undefined }

  const proxied = buildProxiedAssetUrlWithEnv(
    "https://pbs.twimg.com/media/example.jpg?format=jpg&name=large",
    request,
    env,
  )
  if (
    proxied !==
      "https://media.example.com/functions/v1/media-proxy?url=https%3A%2F%2Fpbs.twimg.com%2Fmedia%2Fexample.jpg%3Fformat%3Djpg%26name%3Dlarge"
  ) {
    throw new Error(`unexpected proxied asset url: ${proxied ?? "null"}`)
  }
})

Deno.test("buildProxiedMediaUrls leaves non-proxied hosts unchanged", () => {
  const request = new Request("http://127.0.0.1:9001/feed", {
    headers: {
      "x-forwarded-host": "media.example.com",
    },
  })
  const env = { get: (_key: string) => undefined }

  const urls = buildProxiedMediaUrlsWithEnv([
    "https://wx3.sinaimg.cn/large/example.jpg",
    "https://pbs.twimg.com/media/example.jpg",
  ], request, 9, env)

  if (JSON.stringify(urls) !== JSON.stringify([
    "https://wx3.sinaimg.cn/large/example.jpg",
    "https://media.example.com/functions/v1/media-proxy?url=https%3A%2F%2Fpbs.twimg.com%2Fmedia%2Fexample.jpg",
  ])) {
    throw new Error(`unexpected proxied media urls: ${JSON.stringify(urls)}`)
  }
})

Deno.test("shouldProxyAssetUrl only accepts configured foreign hosts", () => {
  if (
    buildProxiedAssetUrlWithEnv(
      "https://wx1.sinaimg.cn/large/example.jpg",
      new Request("http://127.0.0.1:9001/feed"),
      { get: (_key: string) => undefined },
    ) !== "https://wx1.sinaimg.cn/large/example.jpg"
  ) {
    throw new Error("expected non-proxied media to stay unchanged")
  }

  if (!shouldProxyAssetUrl("https://video.twimg.com/ext_tw_video/example.mp4")) {
    throw new Error("expected twimg asset to be proxied")
  }

  if (shouldProxyAssetUrl("https://wx1.sinaimg.cn/large/example.jpg")) {
    throw new Error("expected sinaimg asset to stay direct")
  }
})
