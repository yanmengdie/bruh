import { createClient } from "jsr:@supabase/supabase-js@2";
import {
  contractHeaders,
  isAcceptedContractCompatible,
  requestedClientVersion,
} from "../_shared/api_contract.ts";
import { corsHeaders } from "../_shared/cors.ts";
import { resolveSupabaseServiceConfig } from "../_shared/environment.ts";
import {
  type FeedRankingStrategy,
  resolveBackendFeatureFlags,
} from "../_shared/feature_flags.ts";
import {
  extractNormalizedVideoUrl,
  normalizeMediaUrls,
  normalizeSourceUrl,
} from "../_shared/media.ts";
import {
  classifyError,
  createObservationContext,
  logEdgeFailure,
  logEdgeStart,
  logEdgeSuccess,
  responseHeadersWithRequestId,
} from "../_shared/observability.ts";

const feedBaseHeaders = {
  ...corsHeaders,
  "Cache-Control": "no-store, no-cache, must-revalidate, max-age=0",
  Pragma: "no-cache",
  Expires: "0",
};

type FeedRow = {
  id: string;
  source_post_id?: string | null;
  persona_id: string;
  content: string;
  source_type: string;
  source_url: string | null;
  topic: string | null;
  importance_score: number;
  published_at: string;
  media_urls: string[] | null;
  video_url: string | null;
  raw_payload?: Record<string, unknown> | null;
  source_posts?: {
    video_url?: string | null;
    raw_payload?: Record<string, unknown> | null;
  } | null;
};

function resolveFeedId(item: FeedRow): string {
  const preferredId =
    typeof item.source_post_id === "string" && item.source_post_id
      ? item.source_post_id
      : item.id;
  return preferredId.startsWith("feed-") ? preferredId : `feed-${preferredId}`;
}

function resolveVideoUrl(item: FeedRow): string | null {
  return extractNormalizedVideoUrl(item);
}

function sortFeedRows(rows: FeedRow[], rankingStrategy: FeedRankingStrategy) {
  const sorted = rows.slice();
  if (rankingStrategy === "importance") {
    return sorted.sort((left, right) =>
      right.importance_score - left.importance_score ||
      Date.parse(right.published_at) - Date.parse(left.published_at) ||
      resolveFeedId(right).localeCompare(resolveFeedId(left))
    );
  }

  return sorted.sort((left, right) =>
    Date.parse(right.published_at) - Date.parse(left.published_at) ||
    resolveFeedId(right).localeCompare(resolveFeedId(left))
  );
}

function mapFeed(rows: FeedRow[], rankingStrategy: FeedRankingStrategy) {
  return sortFeedRows(rows, rankingStrategy).map((item) => ({
    id: resolveFeedId(item),
    personaId: item.persona_id,
    content: item.content,
    sourceType: item.source_type,
    sourceUrl: normalizeSourceUrl(item.source_url),
    topic: item.topic,
    importanceScore: item.importance_score,
    publishedAt: item.published_at,
    mediaUrls: normalizeMediaUrls(item.media_urls),
    videoUrl: resolveVideoUrl(item),
  }));
}

Deno.serve(async (request) => {
  const baseResponseHeaders = contractHeaders(feedBaseHeaders, "feed.v1");

  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: baseResponseHeaders });
  }

  const observation = createObservationContext("feed");
  const responseHeaders = responseHeadersWithRequestId(
    baseResponseHeaders,
    observation.requestId,
  );
  const clientVersion = requestedClientVersion(request);
  logEdgeStart(observation, "request_started", {
    method: request.method,
    clientVersion,
  });

  try {
    if (!isAcceptedContractCompatible(request, "feed.v1")) {
      logEdgeSuccess(observation, "request_rejected", {
        status: 412,
        clientVersion,
      });
      return Response.json(
        {
          error: "Requested contract is incompatible with feed.v1",
          errorCategory: "validation",
        },
        { status: 412, headers: responseHeaders },
      );
    }

    const { projectUrl, serviceRoleKey } = resolveSupabaseServiceConfig();
    const featureFlags = resolveBackendFeatureFlags();
    const supabase = createClient(projectUrl, serviceRoleKey);
    const requestUrl = new URL(request.url);
    const since = requestUrl.searchParams.get("since");
    const limitParam = Number.parseInt(
      requestUrl.searchParams.get("limit") ?? "20",
      10,
    );
    const limit = Number.isNaN(limitParam)
      ? 20
      : Math.min(Math.max(limitParam, 1), 100);

    if (since) {
      const sinceDate = new Date(since);
      if (Number.isNaN(sinceDate.getTime())) {
        logEdgeSuccess(observation, "request_rejected", {
          status: 400,
          clientVersion,
        });
        return Response.json(
          { error: "Invalid since parameter", errorCategory: "validation" },
          { status: 400, headers: responseHeaders },
        );
      }
    }

    let sourceQuery = supabase
      .from("source_posts")
      .select(
        "id, persona_id, content, source_type, source_url, topic, importance_score, published_at, media_urls, video_url, raw_payload",
      )
      .in("persona_id", featureFlags.enabledPersonaIds)
      .order("published_at", { ascending: false })
      .order("id", { ascending: false })
      .limit(limit);

    if (since) {
      sourceQuery = sourceQuery.gt(
        "published_at",
        new Date(since).toISOString(),
      );
    }

    if (featureFlags.feedReadSource !== "feed_items") {
      const { data: sourcePosts, error: sourceError } = await sourceQuery;
      if (sourceError && featureFlags.feedReadSource === "source_posts") {
        const errorCategory = classifyError(sourceError.message);
        logEdgeFailure(
          observation,
          "source_posts_query_failed",
          sourceError.message,
          {
            feedReadSource: featureFlags.feedReadSource,
            clientVersion,
          },
        );
        return Response.json(
          { error: sourceError.message, errorCategory },
          { status: 500, headers: responseHeaders },
        );
      }

      if (!sourceError && (sourcePosts?.length ?? 0) > 0) {
        const payload = mapFeed(
          (sourcePosts ?? []) as FeedRow[],
          featureFlags.feedRankingStrategy,
        );
        logEdgeSuccess(observation, "request_succeeded", {
          itemCount: payload.length,
          dataSource: "source_posts",
          rankingStrategy: featureFlags.feedRankingStrategy,
          clientVersion,
        });
        return Response.json(payload, {
          headers: responseHeaders,
        });
      }
    }

    let fallbackQuery = supabase
      .from("feed_items")
      .select(
        "id, source_post_id, persona_id, content, source_type, source_url, topic, importance_score, published_at, media_urls, video_url, source_posts(video_url, raw_payload)",
      )
      .in("persona_id", featureFlags.enabledPersonaIds)
      .order("published_at", { ascending: false })
      .order("source_post_id", { ascending: false })
      .limit(limit);

    if (since) {
      fallbackQuery = fallbackQuery.gt(
        "published_at",
        new Date(since).toISOString(),
      );
    }

    const { data: feedItems, error: feedError } = await fallbackQuery;

    if (feedError) {
      const errorCategory = classifyError(feedError.message);
      logEdgeFailure(
        observation,
        "feed_items_query_failed",
        feedError.message,
        {
          feedReadSource: featureFlags.feedReadSource,
          clientVersion,
        },
      );
      return Response.json(
        { error: feedError.message, errorCategory },
        { status: 500, headers: responseHeaders },
      );
    }

    const payload = mapFeed(
      (feedItems ?? []) as FeedRow[],
      featureFlags.feedRankingStrategy,
    );
    logEdgeSuccess(observation, "request_succeeded", {
      itemCount: payload.length,
      dataSource: "feed_items",
      rankingStrategy: featureFlags.feedRankingStrategy,
      clientVersion,
    });
    return Response.json(payload, {
      headers: responseHeaders,
    });
  } catch (error) {
    const errorCategory = classifyError(error);
    logEdgeFailure(observation, "request_failed", error, {
      clientVersion,
    });
    return Response.json(
      {
        error: error instanceof Error ? error.message : "Unknown error",
        errorCategory,
      },
      { status: 500, headers: responseHeaders },
    );
  }
});
