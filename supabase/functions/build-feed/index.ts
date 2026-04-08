import { createClient } from "jsr:@supabase/supabase-js@2"
import { corsHeaders } from "../_shared/cors.ts"

function extractVideoUrl(value: unknown): string | null {
  if (!value || typeof value !== "object") return null

  const record = value as Record<string, unknown>
  const direct = typeof record.video_url === "string" && record.video_url ? record.video_url : null
  if (direct) return direct

  const rawPayload = record.raw_payload
  if (!rawPayload || typeof rawPayload !== "object") return null

  const payloadRecord = rawPayload as Record<string, unknown>
  const payloadDirect = typeof payloadRecord.videoUrl === "string" && payloadRecord.videoUrl ? payloadRecord.videoUrl : null
  if (payloadDirect) return payloadDirect

  const note = payloadRecord.note
  if (!note || typeof note !== "object") return null

  const noteVideo = (note as Record<string, unknown>).videoUrl
  return typeof noteVideo === "string" && noteVideo ? noteVideo : null
}

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders })
  }

  try {
    const url = Deno.env.get("PROJECT_URL")
    const serviceRoleKey = Deno.env.get("SERVICE_ROLE_KEY")

    if (!url || !serviceRoleKey) {
      return Response.json(
        { error: "Missing Supabase environment variables" },
        { status: 500, headers: corsHeaders },
      )
    }

    const body = request.method === "POST" ? await request.json().catch(() => ({})) : {}
    const limitRaw = Number.parseInt(String(body.limit ?? 100), 10)
    const limit = Number.isNaN(limitRaw) ? 100 : Math.min(Math.max(limitRaw, 1), 500)

    const supabase = createClient(url, serviceRoleKey)
    const { data: sourcePosts, error: sourceError } = await supabase
      .from("source_posts")
      .select("id, persona_id, content, source_type, source_url, topic, importance_score, published_at, media_urls, video_url, raw_payload")
      .order("published_at", { ascending: false })
      .limit(limit)

    if (sourceError) {
      throw new Error(sourceError.message)
    }

    const rows = (sourcePosts ?? []).map((post) => ({
      id: `feed-${post.id}`,
      source_post_id: post.id,
      persona_id: post.persona_id,
      content: post.content,
      source_type: post.source_type,
      source_url: post.source_url,
      topic: post.topic,
      importance_score: post.importance_score,
      published_at: post.published_at,
      media_urls: Array.isArray(post.media_urls) ? post.media_urls : [],
      video_url: extractVideoUrl(post),
      delivered_at: new Date().toISOString(),
    }))

    if (rows.length > 0) {
      const { error: upsertError } = await supabase
        .from("feed_items")
        .upsert(rows, { onConflict: "source_post_id" })

      if (upsertError) {
        throw new Error(upsertError.message)
      }
    }

    return Response.json(
      {
        ok: true,
        sourcePosts: sourcePosts?.length ?? 0,
        feedItems: rows.length,
      },
      { headers: corsHeaders },
    )
  } catch (error) {
    return Response.json(
      { error: error instanceof Error ? error.message : "Unknown error" },
      { status: 500, headers: corsHeaders },
    )
  }
})
