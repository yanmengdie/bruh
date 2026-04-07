import { createClient } from "jsr:@supabase/supabase-js@2"
import { corsHeaders } from "../_shared/cors.ts"
import {
  asString,
  buildEventKey,
  categorizeFeedScore,
  inferInterestTags,
  parseFeedsFromBody,
  parseRssItems,
  scoreNewsRecency,
  stableHash,
} from "../_shared/news.ts"

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders })
  }

  try {
    if (request.method !== "POST") {
      return Response.json({ error: "Method not allowed" }, { status: 405, headers: corsHeaders })
    }

    const projectUrl = Deno.env.get("PROJECT_URL")
    const serviceRoleKey = Deno.env.get("SERVICE_ROLE_KEY")

    if (!projectUrl || !serviceRoleKey) {
      return Response.json({ error: "Missing Supabase environment variables" }, { status: 500, headers: corsHeaders })
    }

    const body = await request.json().catch(() => ({})) as Record<string, unknown>
    const feeds = parseFeedsFromBody(body)
    const timeoutMsRaw = Number.parseInt(asString(body.timeoutMs) || "12000", 10)
    const timeoutMs = Number.isNaN(timeoutMsRaw) ? 12000 : Math.min(Math.max(timeoutMsRaw, 3000), 20000)

    const supabase = createClient(projectUrl, serviceRoleKey)
    const fetchedAt = new Date().toISOString()
    const articles: Array<Record<string, unknown>> = []
    const results: Array<Record<string, unknown>> = []

    for (const feed of feeds) {
      const controller = new AbortController()
      const timeout = setTimeout(() => controller.abort(), timeoutMs)

      try {
        const response = await fetch(feed.url, {
          headers: {
            "User-Agent": "bruh-news-bot/1.0",
            "Accept": "application/rss+xml, application/xml, text/xml;q=0.9, */*;q=0.8",
          },
          signal: controller.signal,
        })
        clearTimeout(timeout)

        if (!response.ok) {
          results.push({ feed: feed.slug, ok: false, status: response.status })
          continue
        }

        const xml = await response.text()
        const items = parseRssItems(xml)
        const normalized = items
          .filter((item) => item.title && item.link)
          .map((item) => {
            const publishedAt = new Date(item.pubDate || Date.now()).toISOString()
            const id = `news-${stableHash(item.link)}`
            const summary = item.description || item.title
            const interestTags = inferInterestTags(`${item.title} ${summary}`, feed.category)
            const importanceScore = categorizeFeedScore(feed.category) + scoreNewsRecency(publishedAt)

            return {
              id,
              source_name: feed.sourceName,
              source_type: "rss",
              feed_slug: feed.slug,
              title: item.title,
              summary,
              article_url: item.link,
              category: feed.category,
              interest_tags: interestTags,
              published_at: publishedAt,
              fetched_at: fetchedAt,
              importance_score: importanceScore,
              raw_payload: {
                guid: item.guid,
                title: item.title,
                link: item.link,
                description: item.description,
                pubDate: item.pubDate,
                eventKey: buildEventKey(item.title, feed.category),
              },
            }
          })

        const deduped = Array.from(new Map(normalized.map((item) => [item.article_url as string, item])).values())
        articles.push(...deduped)
        results.push({ feed: feed.slug, ok: true, fetched: deduped.length })
      } catch (error) {
        clearTimeout(timeout)
        results.push({
          feed: feed.slug,
          ok: false,
          error: error instanceof Error ? error.message : "Unknown error",
        })
      }
    }

    let inserted = 0
    let updated = 0
    if (articles.length > 0) {
      const dedupedArticles = Array.from(new Map(articles.map((item) => [item.article_url as string, item])).values())
      const urls = dedupedArticles.map((item) => item.article_url as string)
      const { data: existingRows, error: existingError } = await supabase
        .from("news_articles")
        .select("id, article_url")
        .in("article_url", urls)

      if (existingError && !existingError.message.includes("news_articles")) {
        throw new Error(existingError.message)
      }

      const existingByUrl = new Map((existingRows ?? []).map((row) => [row.article_url as string, row.id as string]))
      const rowsToUpsert = dedupedArticles.map((item) => ({
        ...item,
        id: existingByUrl.get(item.article_url as string) ?? item.id,
      }))

      const { error } = await supabase
        .from("news_articles")
        .upsert(rowsToUpsert, { onConflict: "id" })

      if (error) {
        throw new Error(error.message)
      }

      inserted = rowsToUpsert.filter((item) => !existingByUrl.has(item.article_url as string)).length
      updated = rowsToUpsert.length - inserted
    }

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
    )
  } catch (error) {
    return Response.json(
      { error: error instanceof Error ? error.message : "Unknown error" },
      { status: 500, headers: corsHeaders },
    )
  }
})
