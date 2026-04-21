import {
  extractNormalizedVideoUrl,
  normalizeAssetUrl,
  normalizeMediaUrls,
  normalizeSourceUrl,
} from "./media.ts"

Deno.test("normalizeSourceUrl allows http and strips fragments", () => {
  const normalized = normalizeSourceUrl("http://example.com/story?id=1#section-2")
  if (normalized !== "http://example.com/story?id=1") {
    throw new Error(`unexpected normalized source url: ${normalized ?? "null"}`)
  }
})

Deno.test("normalizeAssetUrl requires https and rejects private hosts", () => {
  if (normalizeAssetUrl("http://cdn.example.com/file.jpg") !== null) {
    throw new Error("expected insecure asset url to be rejected")
  }

  if (normalizeAssetUrl("https://localhost/file.jpg") !== null) {
    throw new Error("expected localhost asset url to be rejected")
  }

  const normalized = normalizeAssetUrl("https://cdn.example.com/file.jpg#preview")
  if (normalized !== "https://cdn.example.com/file.jpg") {
    throw new Error(`unexpected normalized asset url: ${normalized ?? "null"}`)
  }
})

Deno.test("normalizeAssetUrl upgrades trusted Weibo video CDN assets", () => {
  const normalized = normalizeAssetUrl(
    "http://f.video.weibocdn.com/o0/sample.mp4?label=mp4_hd#preview",
  )
  if (normalized !== "https://f.video.weibocdn.com/o0/sample.mp4?label=mp4_hd") {
    throw new Error(`unexpected normalized Weibo asset url: ${normalized ?? "null"}`)
  }

  const podcast = normalizeAssetUrl("http://podcast.video.weibocdn.com/ol/sample.mp3")
  if (podcast !== "https://podcast.video.weibocdn.com/ol/sample.mp3") {
    throw new Error(`unexpected normalized Weibo podcast url: ${podcast ?? "null"}`)
  }
})

Deno.test("normalizeMediaUrls deduplicates and limits image lists", () => {
  const urls = normalizeMediaUrls([
    "https://cdn.example.com/1.jpg#hero",
    "https://cdn.example.com/1.jpg",
    "javascript:alert(1)",
    "https://cdn.example.com/2.jpg",
    "https://cdn.example.com/3.jpg",
  ], 2)

  if (JSON.stringify(urls) !== JSON.stringify([
    "https://cdn.example.com/1.jpg",
    "https://cdn.example.com/2.jpg",
  ])) {
    throw new Error(`unexpected normalized media urls: ${JSON.stringify(urls)}`)
  }
})

Deno.test("extractNormalizedVideoUrl reads direct and payload-backed candidates", () => {
  const direct = extractNormalizedVideoUrl({
    video_url: "https://video.example.com/direct.mp4#t=10",
  })
  if (direct !== "https://video.example.com/direct.mp4") {
    throw new Error(`unexpected direct video url: ${direct ?? "null"}`)
  }

  const nested = extractNormalizedVideoUrl({
    raw_payload: {
      note: {
        videoUrl: "https://video.example.com/from-note.mp4#clip",
      },
    },
  })
  if (nested !== "https://video.example.com/from-note.mp4") {
    throw new Error(`unexpected nested video url: ${nested ?? "null"}`)
  }

  const trustedWeibo = extractNormalizedVideoUrl({
    video_url: "http://f.video.weibocdn.com/o0/from-weibo.mp4",
  })
  if (trustedWeibo !== "https://f.video.weibocdn.com/o0/from-weibo.mp4") {
    throw new Error(`unexpected Weibo video url: ${trustedWeibo ?? "null"}`)
  }
})
