import { createClient } from "jsr:@supabase/supabase-js@2"
import { corsHeaders } from "../_shared/cors.ts"

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
      .select("id, persona_id, content, source_type, source_url, topic, importance_score, published_at")
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
