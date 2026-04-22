import { createClient } from "jsr:@supabase/supabase-js@2";
import { corsHeaders } from "../_shared/cors.ts";
import { resolveSupabaseServiceConfig } from "../_shared/environment.ts";
import {
  extractNormalizedVideoUrl,
  normalizeSourceUrl,
} from "../_shared/media.ts";
import {
  mirrorMediaUrls,
  mirrorVideoUrl,
} from "../_shared/media_cache.ts";
import {
  classifyError,
  createObservationContext,
  logEdgeFailure,
  logEdgeStart,
  logEdgeSuccess,
} from "../_shared/observability.ts";
import {
  claimPipelineJob,
  completePipelineJob,
} from "../_shared/pipeline_lock.ts";

const port = Number(Deno.env.get("PORT") ?? "8000");
const mirrorConcurrency = 6;

async function mapWithConcurrency<T, R>(
  items: T[],
  concurrency: number,
  mapper: (item: T, index: number) => Promise<R>,
) {
  const results: R[] = new Array(items.length)
  let nextIndex = 0

  async function worker() {
    while (true) {
      const currentIndex = nextIndex
      nextIndex += 1
      if (currentIndex >= items.length) return
      results[currentIndex] = await mapper(items[currentIndex], currentIndex)
    }
  }

  await Promise.all(
    Array.from({ length: Math.min(Math.max(concurrency, 1), items.length || 1) }, () => worker()),
  )
  return results
}

Deno.serve({ port }, async (request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  const observation = createObservationContext("build-feed");
  logEdgeStart(observation, "job_started", {
    method: request.method,
  });

  try {
    const { projectUrl, serviceRoleKey } = resolveSupabaseServiceConfig();
    const supabase = createClient(projectUrl, serviceRoleKey);
    const lock = await claimPipelineJob(supabase, "build-feed", 10 * 60);
    if (!lock.acquired) {
      logEdgeSuccess(observation, "job_skipped", {
        reason: "already_running",
        lockedBy: lock.currentOwnerId,
        lockedUntil: lock.expiresAt,
      });
      return Response.json(
        {
          ok: true,
          skipped: true,
          reason: "already_running",
          lockedBy: lock.currentOwnerId,
          lockedUntil: lock.expiresAt,
        },
        { headers: corsHeaders },
      );
    }

    try {
      const body = request.method === "POST"
        ? await request.json().catch(() => ({}))
        : {};
      const limitRaw = Number.parseInt(String(body.limit ?? 300), 10);
      const limit = Number.isNaN(limitRaw)
        ? 300
        : Math.min(Math.max(limitRaw, 1), 500);

      const { data: sourcePosts, error: sourceError } = await supabase
        .from("source_posts")
        .select(
          "id, persona_id, content, source_type, source_url, topic, importance_score, published_at, media_urls, video_url, raw_payload",
        )
        .order("published_at", { ascending: false })
        .order("id", { ascending: false })
        .limit(limit);

      if (sourceError) {
        throw new Error(sourceError.message);
      }

      const rows = await mapWithConcurrency(sourcePosts ?? [], mirrorConcurrency, async (post) => ({
        id: `feed-${post.id}`,
        source_post_id: post.id,
        persona_id: post.persona_id,
        content: post.content,
        source_type: post.source_type,
        source_url: normalizeSourceUrl(post.source_url),
        topic: post.topic,
        importance_score: post.importance_score,
        published_at: post.published_at,
        media_urls: await mirrorMediaUrls(post.media_urls),
        video_url: await mirrorVideoUrl(extractNormalizedVideoUrl(post)),
        delivered_at: new Date().toISOString(),
      }));

      if (rows.length > 0) {
        const { error: upsertError } = await supabase
          .from("feed_items")
          .upsert(rows, { onConflict: "source_post_id" });

        if (upsertError) {
          throw new Error(upsertError.message);
        }
      }

      await completePipelineJob(supabase, "build-feed", lock.ownerId, true);
      logEdgeSuccess(observation, "job_succeeded", {
        sourcePostCount: sourcePosts?.length ?? 0,
        feedItemCount: rows.length,
      });
      return Response.json(
        {
          ok: true,
          sourcePosts: sourcePosts?.length ?? 0,
          feedItems: rows.length,
        },
        { headers: corsHeaders },
      );
    } catch (error) {
      logEdgeFailure(observation, "job_failed", error, {
        ownerId: lock.ownerId,
      });
      await completePipelineJob(
        supabase,
        "build-feed",
        lock.ownerId,
        false,
        error instanceof Error ? error.message : String(error),
      );
      throw error;
    }
  } catch (error) {
    const errorCategory = classifyError(error);
    logEdgeFailure(observation, "request_failed", error);
    return Response.json(
      {
        error: error instanceof Error ? error.message : "Unknown error",
        errorCategory,
      },
      { status: 500, headers: corsHeaders },
    );
  }
});
