import { createClient } from "jsr:@supabase/supabase-js@2";
import { corsHeaders } from "../_shared/cors.ts";
import { resolveSupabaseServiceConfig } from "../_shared/environment.ts";
import { resolveBackendFeatureFlags } from "../_shared/feature_flags.ts";
import {
  createObservationContext,
  logEdgeFailure,
  logEdgeStart,
  logEdgeSuccess,
} from "../_shared/observability.ts";
import {
  claimPipelineJob,
  completePipelineJob,
} from "../_shared/pipeline_lock.ts";
import {
  asString,
  buildEventKey,
  inferInterestTags,
  scoreNewsRecency,
  scorePersonaForEvent,
  stableHash,
} from "../_shared/news.ts";

type NewsArticleRow = {
  id: string;
  title: string;
  summary: string;
  article_url: string;
  source_name: string;
  category: string;
  interest_tags: string[];
  published_at: string;
  importance_score: number;
};

type EventCluster = {
  eventId: string;
  eventKey: string;
  title: string;
  summary: string;
  category: string;
  interestTags: string[];
  representativeUrl: string;
  representativeSourceName: string;
  articleIds: string[];
  articleCount: number;
  sourceCount: number;
  importanceScore: number;
  publishedAt: string;
};

function aggregateEvents(rows: NewsArticleRow[]) {
  const clusters = new Map<string, EventCluster>();

  for (const row of rows) {
    const eventKey = buildEventKey(row.title, row.category);
    const existing = clusters.get(eventKey);

    if (!existing) {
      clusters.set(eventKey, {
        eventId: `event-${stableHash(eventKey)}`,
        eventKey,
        title: row.title,
        summary: row.summary,
        category: row.category,
        interestTags: [
          ...new Set(
            inferInterestTags(`${row.title} ${row.summary}`, row.category)
              .concat(row.interest_tags ?? []),
          ),
        ],
        representativeUrl: row.article_url,
        representativeSourceName: row.source_name,
        articleIds: [row.id],
        articleCount: 1,
        sourceCount: 1,
        importanceScore: row.importance_score +
          scoreNewsRecency(row.published_at),
        publishedAt: row.published_at,
      });
      continue;
    }

    existing.articleIds.push(row.id);
    existing.articleCount += 1;
    existing.sourceCount += 1;
    existing.importanceScore = Math.max(
      existing.importanceScore,
      row.importance_score + scoreNewsRecency(row.published_at),
    ) + 0.35;
    existing.interestTags = [
      ...new Set(existing.interestTags.concat(row.interest_tags ?? [])),
    ];

    if (Date.parse(row.published_at) > Date.parse(existing.publishedAt)) {
      existing.title = row.title;
      existing.summary = row.summary;
      existing.representativeUrl = row.article_url;
      existing.representativeSourceName = row.source_name;
      existing.publishedAt = row.published_at;
    }
  }

  return [...clusters.values()]
    .sort((left, right) =>
      right.importanceScore - left.importanceScore ||
      Date.parse(right.publishedAt) - Date.parse(left.publishedAt)
    );
}

const port = Number(Deno.env.get("PORT") ?? "8000");

Deno.serve({ port }, async (request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  const observation = createObservationContext("build-news-events");
  logEdgeStart(observation, "job_started", {
    method: request.method,
  });

  try {
    if (request.method !== "POST") {
      logEdgeSuccess(observation, "request_rejected", { status: 405 });
      return Response.json({ error: "Method not allowed" }, {
        status: 405,
        headers: corsHeaders,
      });
    }

    const { projectUrl, serviceRoleKey } = resolveSupabaseServiceConfig();
    const featureFlags = resolveBackendFeatureFlags();
    const supabase = createClient(projectUrl, serviceRoleKey);
    const lock = await claimPipelineJob(supabase, "build-news-events", 15 * 60);
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
      const body = await request.json().catch(() => ({})) as Record<
        string,
        unknown
      >;
      const hoursRaw = Number.parseInt(
        asString(body.lookbackHours) || "72",
        10,
      );
      const lookbackHours = Number.isNaN(hoursRaw)
        ? 72
        : Math.min(Math.max(hoursRaw, 12), 168);
      const sinceIso = new Date(Date.now() - lookbackHours * 60 * 60 * 1000)
        .toISOString();

      const { data: rows, error } = await supabase
        .from("news_articles")
        .select(
          "id, title, summary, article_url, source_name, category, interest_tags, published_at, importance_score",
        )
        .gte("published_at", sinceIso)
        .order("published_at", { ascending: false })
        .limit(300);

      if (error) {
        throw new Error(error.message);
      }

      const events = aggregateEvents((rows ?? []) as NewsArticleRow[]);
      const topEvents = events.slice(0, 30);

      if (topEvents.length > 0) {
        const eventRows = topEvents.map((event, index) => ({
          id: event.eventId,
          event_key: event.eventKey,
          title: event.title,
          summary: event.summary,
          category: event.category,
          interest_tags: event.interestTags,
          representative_url: event.representativeUrl,
          representative_source_name: event.representativeSourceName,
          article_count: event.articleCount,
          source_count: event.sourceCount,
          importance_score: Number(
            (event.importanceScore + event.articleCount * 0.25).toFixed(3),
          ),
          global_rank: index < 10 ? index + 1 : null,
          is_global_top: index < 10,
          published_at: event.publishedAt,
          updated_at: new Date().toISOString(),
          raw_article_ids: event.articleIds,
        }));

        const { error: eventError } = await supabase
          .from("news_events")
          .upsert(eventRows, { onConflict: "id" });

        if (eventError) {
          throw new Error(eventError.message);
        }

        const joinRows = topEvents.flatMap((event) =>
          event.articleIds.map((articleId) => ({
            event_id: event.eventId,
            article_id: articleId,
          }))
        );

        const { error: joinError } = await supabase
          .from("news_event_articles")
          .upsert(joinRows, { onConflict: "event_id,article_id" });

        if (joinError) {
          throw new Error(joinError.message);
        }

        const scoreRows = topEvents.flatMap((event) =>
          featureFlags.enabledPersonaIds.map((personaId) => {
            const scoring = scorePersonaForEvent(
              personaId,
              event.title,
              event.summary,
              event.interestTags,
            );
            return {
              event_id: event.eventId,
              persona_id: personaId,
              score: Number(
                (scoring.score + scoreNewsRecency(event.publishedAt)).toFixed(
                  3,
                ),
              ),
              reason_codes: scoring.reasonCodes,
              matched_interests: scoring.matchedInterests,
              updated_at: new Date().toISOString(),
            };
          })
        );

        const { error: scoreError } = await supabase
          .from("persona_news_scores")
          .upsert(scoreRows, { onConflict: "event_id,persona_id" });

        if (scoreError) {
          throw new Error(scoreError.message);
        }
      }

      await completePipelineJob(
        supabase,
        "build-news-events",
        lock.ownerId,
        true,
      );
      logEdgeSuccess(observation, "job_succeeded", {
        lookbackHours,
        articleCount: (rows ?? []).length,
        eventCount: topEvents.length,
        personaCount: featureFlags.enabledPersonaIds.length,
      });
      return Response.json(
        {
          ok: true,
          lookbackHours,
          articles: (rows ?? []).length,
          events: topEvents.length,
          personaCount: featureFlags.enabledPersonaIds.length,
          globalTop: topEvents.slice(0, 10).map((event, index) => ({
            rank: index + 1,
            title: event.title,
            category: event.category,
            interestTags: event.interestTags,
          })),
        },
        { headers: corsHeaders },
      );
    } catch (error) {
      logEdgeFailure(observation, "job_failed", error, {
        ownerId: lock.ownerId,
      });
      await completePipelineJob(
        supabase,
        "build-news-events",
        lock.ownerId,
        false,
        error instanceof Error ? error.message : String(error),
      );
      throw error;
    }
  } catch (error) {
    logEdgeFailure(observation, "request_failed", error);
    return Response.json(
      { error: error instanceof Error ? error.message : "Unknown error" },
      { status: 500, headers: corsHeaders },
    );
  }
});
