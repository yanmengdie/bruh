import { createClient } from "jsr:@supabase/supabase-js@2";
import { sanitizeExternalContent } from "../_shared/content_safety.ts";
import { corsHeaders } from "../_shared/cors.ts";
import { resolveSupabaseServiceConfig } from "../_shared/environment.ts";
import { normalizeSourceUrl } from "../_shared/media.ts";
import {
  createObservationContext,
  logEdgeEvent,
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
  categorizeFeedScore,
  inferInterestTags,
  parseFeedsFromBody,
  parseRssItems,
  scoreNewsRecency,
  stableHash,
} from "../_shared/news.ts";

type NewsArticleUpsertRow = {
  id: string;
  source_name: string;
  source_type: string;
  feed_slug: string;
  title: string;
  summary: string;
  article_url: string;
  category: string;
  interest_tags: string[];
  published_at: string;
  fetched_at: string;
  importance_score: number;
  raw_payload: {
    guid: string;
    title: string;
    link: string;
    description: string;
    pubDate: string;
    eventKey: string;
  };
};

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  const observation = createObservationContext("ingest-top-news");
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
    const supabase = createClient(projectUrl, serviceRoleKey);
    const lock = await claimPipelineJob(supabase, "ingest-top-news", 20 * 60);
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
      const feeds = parseFeedsFromBody(body);
      const timeoutMsRaw = Number.parseInt(
        asString(body.timeoutMs) || "12000",
        10,
      );
      const timeoutMs = Number.isNaN(timeoutMsRaw)
        ? 12000
        : Math.min(Math.max(timeoutMsRaw, 3000), 20000);

      const fetchedAt = new Date().toISOString();
      const articles: NewsArticleUpsertRow[] = [];
      const results: Array<Record<string, unknown>> = [];
      const contentSafety = { blocked: 0, sanitized: 0 };

      for (const feed of feeds) {
        const controller = new AbortController();
        const timeout = setTimeout(() => controller.abort(), timeoutMs);

        try {
          const response = await fetch(feed.url, {
            headers: {
              "User-Agent": "bruh-news-bot/1.0",
              "Accept":
                "application/rss+xml, application/xml, text/xml;q=0.9, */*;q=0.8",
            },
            signal: controller.signal,
          });
          clearTimeout(timeout);

          if (!response.ok) {
            results.push({
              feed: feed.slug,
              ok: false,
              status: response.status,
            });
            continue;
          }

          const xml = await response.text();
          const items = parseRssItems(xml);
          const normalized: NewsArticleUpsertRow[] = items
            .flatMap((item) => {
              const articleUrl = normalizeSourceUrl(item.link);
              if (!item.title || !articleUrl) {
                return [];
              }

              const titleSafety = sanitizeExternalContent(item.title, {
                maxLength: 220,
              });
              if (titleSafety.blocked || !titleSafety.text) {
                contentSafety.blocked += 1;
                return [];
              }
              if (titleSafety.sanitized) {
                contentSafety.sanitized += 1;
              }

              const summarySafety = sanitizeExternalContent(
                item.description || item.title,
                { maxLength: 420 },
              );
              let summary = titleSafety.text;
              if (!summarySafety.blocked && summarySafety.text) {
                summary = summarySafety.text;
                if (summarySafety.sanitized) {
                  contentSafety.sanitized += 1;
                }
              } else if (summarySafety.blocked) {
                contentSafety.blocked += 1;
              }

              const publishedAt = new Date(item.pubDate || Date.now())
                .toISOString();
              const id = `news-${stableHash(articleUrl)}`;
              const interestTags = inferInterestTags(
                `${titleSafety.text} ${summary}`,
                feed.category,
              );
              const importanceScore = categorizeFeedScore(feed.category) +
                scoreNewsRecency(publishedAt);

              return [{
                id,
                source_name: feed.sourceName,
                source_type: "rss",
                feed_slug: feed.slug,
                title: titleSafety.text,
                summary,
                article_url: articleUrl,
                category: feed.category,
                interest_tags: interestTags,
                published_at: publishedAt,
                fetched_at: fetchedAt,
                importance_score: importanceScore,
                raw_payload: {
                  guid: item.guid,
                  title: titleSafety.text,
                  link: articleUrl,
                  description: summary,
                  pubDate: item.pubDate,
                  eventKey: buildEventKey(titleSafety.text, feed.category),
                },
              }];
            });

          const deduped = Array.from(
            new Map(normalized.map((item) => [item.article_url, item]))
              .values(),
          );
          articles.push(...deduped);
          results.push({ feed: feed.slug, ok: true, fetched: deduped.length });
        } catch (error) {
          clearTimeout(timeout);
          results.push({
            feed: feed.slug,
            ok: false,
            error: error instanceof Error ? error.message : "Unknown error",
          });
        }
      }

      if (contentSafety.blocked > 0 || contentSafety.sanitized > 0) {
        logEdgeEvent("ingest-top-news", "content_safety_applied", {
          blocked: contentSafety.blocked,
          sanitized: contentSafety.sanitized,
          feedCount: feeds.length,
        });
      }

      let inserted = 0;
      let updated = 0;
      if (articles.length > 0) {
        const dedupedArticles = Array.from(
          new Map(articles.map((item) => [item.article_url, item])).values(),
        );
        const urls = dedupedArticles.map((item) => item.article_url);
        const { data: existingRows, error: existingError } = await supabase
          .from("news_articles")
          .select("id, article_url")
          .in("article_url", urls);

        if (existingError && !existingError.message.includes("news_articles")) {
          throw new Error(existingError.message);
        }

        const existingByUrl = new Map(
          (existingRows ?? []).map((
            row,
          ) => [row.article_url as string, row.id as string]),
        );
        const rowsToUpsert = dedupedArticles.map((item) => ({
          ...item,
          id: existingByUrl.get(item.article_url) ?? item.id,
        }));

        const { error } = await supabase
          .from("news_articles")
          .upsert(rowsToUpsert, { onConflict: "id" });

        if (error) {
          throw new Error(error.message);
        }

        inserted = rowsToUpsert.filter((item) =>
          !existingByUrl.has(item.article_url)
        ).length;
        updated = rowsToUpsert.length - inserted;
      }

      await completePipelineJob(
        supabase,
        "ingest-top-news",
        lock.ownerId,
        true,
      );
      logEdgeSuccess(observation, "job_succeeded", {
        feedCount: feeds.length,
        articleCount: articles.length,
        inserted,
        updated,
      });
      return Response.json(
        {
          ok: true,
          fetchedAt,
          feeds: results,
          articles: articles.length,
          inserted,
          updated,
        },
        { headers: corsHeaders },
      );
    } catch (error) {
      logEdgeFailure(observation, "job_failed", error, {
        ownerId: lock.ownerId,
      });
      await completePipelineJob(
        supabase,
        "ingest-top-news",
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
