import { createClient } from "jsr:@supabase/supabase-js@2"
import { corsHeaders } from "../_shared/cors.ts"

const feedResponseHeaders = {
  ...corsHeaders,
  "Cache-Control": "no-store, no-cache, must-revalidate, max-age=0",
  Pragma: "no-cache",
  Expires: "0",
}

type FeedRow = {
  id: string
  persona_id: string
  content: string
  source_type: string
  source_url: string | null
  topic: string | null
  importance_score: number
  published_at: string
  media_urls: string[] | null
  video_url: string | null
  raw_payload?: Record<string, unknown> | null
  source_posts?: {
    video_url?: string | null
    raw_payload?: Record<string, unknown> | null
  } | null
}

function resolveVideoUrl(item: FeedRow): string | null {
  if (typeof item.video_url === "string" && item.video_url) {
    return item.video_url
  }

  const mergedPayloadSource = item.source_posts?.raw_payload ?? item.raw_payload
  const mergedVideoUrl = item.source_posts?.video_url
  if (typeof mergedVideoUrl === "string" && mergedVideoUrl) {
    return mergedVideoUrl
  }

  const rawPayload = mergedPayloadSource
  if (!rawPayload || typeof rawPayload !== "object") return null

  const payloadDirect = rawPayload.videoUrl
  if (typeof payloadDirect === "string" && payloadDirect) {
    return payloadDirect
  }

  const note = rawPayload.note
  if (!note || typeof note !== "object") return null

  const noteVideo = (note as Record<string, unknown>).videoUrl
  return typeof noteVideo === "string" && noteVideo ? noteVideo : null
}

function mapFeed(rows: FeedRow[]) {
  return rows.map((item) => ({
    id: item.id,
    personaId: item.persona_id,
    content: item.content,
    sourceType: item.source_type,
    sourceUrl: item.source_url,
    topic: item.topic,
    importanceScore: item.importance_score,
    publishedAt: item.published_at,
    mediaUrls: Array.isArray(item.media_urls) ? item.media_urls : [],
    videoUrl: resolveVideoUrl(item),
  }))
}

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: feedResponseHeaders })
  }

  try {
    const url = Deno.env.get("PROJECT_URL")
    const serviceRoleKey = Deno.env.get("SERVICE_ROLE_KEY")

    if (!url || !serviceRoleKey) {
      return Response.json(
        { error: "Missing Supabase environment variables" },
        { status: 500, headers: feedResponseHeaders },
      )
    }

    const supabase = createClient(url, serviceRoleKey)
    const requestUrl = new URL(request.url)
    const since = requestUrl.searchParams.get("since")
    const limitParam = Number.parseInt(requestUrl.searchParams.get("limit") ?? "20", 10)
    const limit = Number.isNaN(limitParam) ? 20 : Math.min(Math.max(limitParam, 1), 100)

    if (since) {
      const sinceDate = new Date(since)
      if (Number.isNaN(sinceDate.getTime())) {
        return Response.json(
          { error: "Invalid since parameter" },
          { status: 400, headers: feedResponseHeaders },
        )
      }
    }

    let feedQuery = supabase
      .from("feed_items")
      .select("id, persona_id, content, source_type, source_url, topic, importance_score, published_at, media_urls, video_url, source_posts(video_url, raw_payload)")
      .order("published_at", { ascending: false })
      .limit(limit)

    if (since) {
      feedQuery = feedQuery.gt("published_at", new Date(since).toISOString())
    }

    const { data: feedItems, error: feedError } = await feedQuery

    if (feedError && !feedError.message.includes("feed_items")) {
      return Response.json(
        { error: feedError.message },
        { status: 500, headers: feedResponseHeaders },
      )
    }

    if ((feedItems?.length ?? 0) > 0) {
      return Response.json(mapFeed((feedItems ?? []) as FeedRow[]), { headers: feedResponseHeaders })
    }

    let sourceQuery = supabase
      .from("source_posts")
      .select("id, persona_id, content, source_type, source_url, topic, importance_score, published_at, media_urls, video_url, raw_payload")
      .order("published_at", { ascending: false })
      .limit(limit)

    if (since) {
      sourceQuery = sourceQuery.gt("published_at", new Date(since).toISOString())
    }

    const { data: sourcePosts, error: sourceError } = await sourceQuery

    if (sourceError) {
      return Response.json(
        { error: sourceError.message },
        { status: 500, headers: feedResponseHeaders },
      )
    }

    return Response.json(mapFeed((sourcePosts ?? []) as FeedRow[]), { headers: feedResponseHeaders })
  } catch (error) {
    return Response.json(
      { error: error instanceof Error ? error.message : "Unknown error" },
      { status: 500, headers: feedResponseHeaders },
    )
  }
})
