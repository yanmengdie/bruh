import { createClient } from "jsr:@supabase/supabase-js@2"
import { corsHeaders } from "../_shared/cors.ts"
import { defaultUsernames, normalizeUsername, resolvePersona } from "../_shared/personas.ts"

type ApifyItem = Record<string, unknown>

type ActorAttempt = {
  name: string
  input: Record<string, unknown>
}

type ActorAttemptSummary = {
  name: string
  status: string
  statusMessage: string | null
  itemCount: number
}

type ActorRunResult = {
  actorId: string
  matchedAttempt: string | null
  summaries: ActorAttemptSummary[]
  items: ApifyItem[]
  blockedReason: string | null
}

type NormalizedPost = {
  id: string
  personaId: string
  content: string
  sourceType: "x"
  sourceUrl: string | null
  topic: string | null
  importanceScore: number
  publishedAt: string
  rawAuthorUsername: string
  rawPayload: ApifyItem
}

function extractString(value: unknown): string | null {
  return typeof value === "string" && value.trim().length > 0 ? value.trim() : null
}

function extractAuthorUsername(item: ApifyItem): string | null {
  const candidates = [
    item.authorUsername,
    item.userName,
    item.username,
    item.screenName,
    item.screen_name,
    (item.author as Record<string, unknown> | undefined)?.userName,
    (item.author as Record<string, unknown> | undefined)?.username,
    (item.author as Record<string, unknown> | undefined)?.screenName,
    (item.author as Record<string, unknown> | undefined)?.screen_name,
    (item.user as Record<string, unknown> | undefined)?.screen_name,
    (item.user as Record<string, unknown> | undefined)?.username,
    (item.user as Record<string, unknown> | undefined)?.userName,
  ]

  for (const candidate of candidates) {
    const username = extractString(candidate)
    if (username) {
      return normalizeUsername(username)
    }
  }

  return null
}

function extractPostId(item: ApifyItem, sourceUrl: string | null): string | null {
  const candidates = [item.id_str, item.id, item.tweetId, item.postId, item.restId]
  for (const candidate of candidates) {
    const value = extractString(candidate)
    if (value) {
      return value
    }
  }

  if (sourceUrl) {
    const match = sourceUrl.match(/status\/(\d+)/)
    if (match?.[1]) {
      return match[1]
    }
  }

  return null
}

function extractContent(item: ApifyItem): string | null {
  const candidates = [item.fullText, item.full_text, item.text, item.description]
  for (const candidate of candidates) {
    const value = extractString(candidate)
    if (value) {
      return value
    }
  }
  return null
}

function extractSourceUrl(item: ApifyItem, username: string | null, postId: string | null): string | null {
  const directUrl = extractString(item.url) ?? extractString(item.twitterUrl)
  if (directUrl) {
    return directUrl
  }

  const permalink = extractString(item.permalink)
  if (permalink && username) {
    return permalink.startsWith("http") ? permalink : `https://x.com${permalink}`
  }

  if (username && postId) {
    return `https://x.com/${username}/status/${postId}`
  }
  return null
}

function extractPublishedAt(item: ApifyItem): string | null {
  const candidates = [item.createdAt, item.created_at, item.timestamp, item.publishedAt, item.published_at]
  for (const candidate of candidates) {
    const value = extractString(candidate)
    if (!value) continue
    const date = new Date(value)
    if (!Number.isNaN(date.getTime())) {
      return date.toISOString()
    }
  }
  return null
}

function extractMetricNumber(value: unknown): number {
  if (typeof value === "number" && Number.isFinite(value)) {
    return value
  }

  if (typeof value === "string") {
    const parsed = Number.parseFloat(value.replace(/,/g, ""))
    return Number.isFinite(parsed) ? parsed : 0
  }

  return 0
}

function normalizeContentForQualityCheck(content: string): string {
  return content
    .replace(/https?:\/\/\S+/g, " ")
    .replace(/@\w+/g, " ")
    .replace(/[#*_`~]/g, " ")
    .replace(/\s+/g, " ")
    .trim()
}

function isRetweet(item: ApifyItem, content: string): boolean {
  if ((item.retweeted_status as Record<string, unknown> | undefined) != null) {
    return true
  }

  return /^RT\s+@/i.test(content)
}

function isLowQualityContent(item: ApifyItem, content: string): boolean {
  if (isRetweet(item, content)) {
    return true
  }

  const normalized = normalizeContentForQualityCheck(content)
  if (normalized.length < 12) {
    return true
  }

  if (/^https?:\/\/\S+$/i.test(content.trim())) {
    return true
  }

  return false
}

function computeImportanceScore(item: ApifyItem): number {
  const likes = extractMetricNumber(item.likeCount) || extractMetricNumber(item.favorite_count)
  const retweets = extractMetricNumber(item.retweetCount) || extractMetricNumber(item.retweet_count)
  const replies = extractMetricNumber(item.replyCount) || extractMetricNumber(item.reply_count)
  const views = extractMetricNumber(item.viewCount) || extractMetricNumber(item.view_count)
  const quotes = extractMetricNumber(item.quoteCount) || extractMetricNumber(item.quote_count)
  const rawScore = 0.5 + Math.min((likes + retweets * 2 + replies + quotes + views / 10000) / 1000, 0.49)
  return Math.round(rawScore * 100) / 100
}

function limitPostsPerUser(posts: NormalizedPost[], limitPerUser: number): NormalizedPost[] {
  const counts = new Map<string, number>()

  return posts
    .sort((left, right) => new Date(right.publishedAt).getTime() - new Date(left.publishedAt).getTime())
    .filter((post) => {
      const current = counts.get(post.rawAuthorUsername) ?? 0
      if (current >= limitPerUser) {
        return false
      }

      counts.set(post.rawAuthorUsername, current + 1)
      return true
    })
}

function buildActorAttempts(usernames: string[], limitPerUser: number): ActorAttempt[] {
  const profileUrls = usernames.map((username) => `https://x.com/${username}`)
  const atHandles = usernames.map((username) => `@${username}`)
  const targetCount = Math.max(limitPerUser * usernames.length, usernames.length)

  return [
    {
      name: "twitterHandles",
      input: {
        twitterHandles: usernames,
        maxItems: targetCount,
        sort: "Latest",
        onlyImage: false,
        onlyQuote: false,
        onlyVideo: false,
        includeSearchTerms: false,
      },
    },
    {
      name: "twitterHandlesWithAt",
      input: {
        twitterHandles: atHandles,
        maxItems: targetCount,
        sort: "Latest",
      },
    },
    {
      name: "searchTermsFromUsers",
      input: {
        searchTerms: usernames.map((username) => `from:${username}`),
        maxItems: targetCount,
        sort: "Latest",
      },
    },
    {
      name: "searchTermsPlainUsers",
      input: {
        searchTerms: usernames,
        maxItems: targetCount,
        sort: "Latest",
      },
    },
    {
      name: "startUrlsProfiles",
      input: {
        startUrls: profileUrls.map((url) => ({ url })),
        maxItems: targetCount,
      },
    },
    {
      name: "twitterUrlsProfiles",
      input: {
        twitterUrls: profileUrls,
        maxItems: targetCount,
      },
    },
    {
      name: "profileUrls",
      input: {
        profileUrls,
        maxItems: targetCount,
      },
    },
    {
      name: "userNames",
      input: {
        userNames: usernames,
        maxItems: targetCount,
      },
    },
  ]
}

function hasUsefulItems(items: ApifyItem[]): boolean {
  return items.some((item) => {
    if (item.noResults === true) return false
    return Boolean(
      extractString(item.fullText) ??
      extractString(item.text) ??
      extractString(item.description) ??
      extractString(item.url) ??
      extractString(item.twitterUrl),
    )
  })
}

async function fetchRunLog(token: string, runId: string): Promise<string | null> {
  const response = await fetch(`https://api.apify.com/v2/actor-runs/${runId}/log?token=${token}`)
  if (!response.ok) {
    return null
  }

  const text = await response.text()
  const trimmed = text.trim()
  if (!trimmed) return null

  return trimmed.split("\n").slice(-40).join("\n")
}

async function runSingleAttempt(token: string, actorId: string, attempt: ActorAttempt) {
  const runResponse = await fetch(
    `https://api.apify.com/v2/acts/${actorId}/runs?token=${token}&waitForFinish=120`,
    {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
      },
      body: JSON.stringify(attempt.input),
    },
  )

  if (!runResponse.ok) {
    const text = await runResponse.text()
    const quotaExceeded = text.includes("Monthly usage hard limit exceeded")
    return {
      summary: {
        name: attempt.name,
        status: quotaExceeded ? "QUOTA_EXCEEDED" : "RUN_START_FAILED",
        statusMessage: text,
        itemCount: 0,
      } satisfies ActorAttemptSummary,
      items: [] as ApifyItem[],
    }
  }

  const runPayload = await runResponse.json()
  const run = runPayload?.data as Record<string, unknown> | undefined
  const runId = extractString(run?.id)
  const status = extractString(run?.status) ?? "UNKNOWN"
  const statusMessage = extractString(run?.statusMessage)

  if (status !== "SUCCEEDED") {
    const logTail = runId ? await fetchRunLog(token, runId) : null
    return {
      summary: {
        name: attempt.name,
        status,
        statusMessage: statusMessage ?? logTail ?? "Actor run did not succeed",
        itemCount: 0,
      } satisfies ActorAttemptSummary,
      items: [] as ApifyItem[],
    }
  }

  const datasetId = extractString(run?.defaultDatasetId)
  if (!datasetId) {
    return {
      summary: {
        name: attempt.name,
        status,
        statusMessage: "Run succeeded but no default dataset was produced",
        itemCount: 0,
      } satisfies ActorAttemptSummary,
      items: [] as ApifyItem[],
    }
  }

  const itemsResponse = await fetch(`https://api.apify.com/v2/datasets/${datasetId}/items?token=${token}&format=json&clean=true`)
  if (!itemsResponse.ok) {
    const text = await itemsResponse.text()
    return {
      summary: {
        name: attempt.name,
        status: "DATASET_FETCH_FAILED",
        statusMessage: text,
        itemCount: 0,
      } satisfies ActorAttemptSummary,
      items: [] as ApifyItem[],
    }
  }

  const itemsPayload = await itemsResponse.json()
  const items = Array.isArray(itemsPayload) ? itemsPayload as ApifyItem[] : []

  return {
    summary: {
      name: attempt.name,
      status,
      statusMessage,
      itemCount: items.length,
    } satisfies ActorAttemptSummary,
    items,
  }
}

function normalizePost(item: ApifyItem): NormalizedPost | null {
  const rawAuthorUsername = extractAuthorUsername(item)
  if (!rawAuthorUsername) return null

  const persona = resolvePersona(rawAuthorUsername)
  if (!persona) return null

  const provisionalUrl = extractString(item.url) ?? extractString(item.twitterUrl)
  const postId = extractPostId(item, provisionalUrl)
  if (!postId) return null

  const content = extractContent(item)
  if (!content) return null
  if (isLowQualityContent(item, content)) return null

  const publishedAt = extractPublishedAt(item)
  if (!publishedAt) return null

  const sourceUrl = extractSourceUrl(item, rawAuthorUsername, postId)

  return {
    id: postId,
    personaId: persona.personaId,
    content,
    sourceType: "x",
    sourceUrl,
    topic: null,
    importanceScore: computeImportanceScore(item),
    publishedAt,
    rawAuthorUsername,
    rawPayload: item,
  }
}

async function runActor(token: string, usernames: string[], limitPerUser: number): Promise<ActorRunResult> {
  const actorId = Deno.env.get("APIFY_ACTOR_ID") ?? "quacker~twitter-scraper"
  const attempts = buildActorAttempts(usernames, limitPerUser)
  const summaries: ActorAttemptSummary[] = []

  for (const attempt of attempts) {
    const result = await runSingleAttempt(token, actorId, attempt)
    summaries.push(result.summary)

    if (result.summary.status === "QUOTA_EXCEEDED") {
      return {
        actorId,
        matchedAttempt: null,
        summaries,
        items: [],
        blockedReason: result.summary.statusMessage,
      }
    }

    if (result.summary.status === "SUCCEEDED" && hasUsefulItems(result.items)) {
      return {
        actorId,
        matchedAttempt: attempt.name,
        summaries,
        items: result.items,
        blockedReason: null,
      }
    }
  }

  return {
    actorId,
    matchedAttempt: null,
    summaries,
    items: [] as ApifyItem[],
    blockedReason: null,
  }
}

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders })
  }

  try {
    const url = Deno.env.get("PROJECT_URL")
    const serviceRoleKey = Deno.env.get("SERVICE_ROLE_KEY")
    const apifyToken = Deno.env.get("APIFY_TOKEN")

    if (!url || !serviceRoleKey || !apifyToken) {
      return Response.json(
        { error: "Missing environment variables" },
        { status: 500, headers: corsHeaders },
      )
    }

    const body = request.method === "POST" ? await request.json().catch(() => ({})) : {}
    const usernames = Array.isArray(body.usernames)
      ? body.usernames.map((value: unknown) => normalizeUsername(String(value))).filter((value: string) => resolvePersona(value))
      : defaultUsernames
    const limitPerUserRaw = Number.parseInt(String(body.limitPerUser ?? 5), 10)
    const limitPerUser = Number.isNaN(limitPerUserRaw) ? 5 : Math.min(Math.max(limitPerUserRaw, 1), 20)
    const debugSample = body.debugSample === true

    const actorResult = await runActor(apifyToken, usernames, limitPerUser)
    const items = actorResult.items
    if (debugSample) {
      return Response.json(
        {
          ok: true,
          actorId: actorResult.actorId,
          matchedAttempt: actorResult.matchedAttempt,
          attempts: actorResult.summaries,
          blockedReason: actorResult.blockedReason,
          usernames,
          totalFetched: items.length,
          sample: items.slice(0, 3),
        },
        { headers: corsHeaders },
      )
    }

    if (actorResult.blockedReason) {
      return Response.json(
        {
          ok: false,
          actorId: actorResult.actorId,
          matchedAttempt: actorResult.matchedAttempt,
          blockedReason: actorResult.blockedReason,
          usernames,
          totalFetched: 0,
          normalized: 0,
          inserted: 0,
          updated: 0,
          skipped: 0,
        },
        { headers: corsHeaders },
      )
    }

    const posts = limitPostsPerUser(
      items
      .map(normalizePost)
      .filter((item): item is NormalizedPost => item !== null),
      limitPerUser,
    )

    const supabase = createClient(url, serviceRoleKey)
    const existingIds = posts.map((post) => post.id)

    let existingIdSet = new Set<string>()
    if (existingIds.length > 0) {
      const { data: existingRows, error: existingError } = await supabase
        .from("source_posts")
        .select("id")
        .in("id", existingIds)

      if (existingError) {
        throw new Error(existingError.message)
      }

      existingIdSet = new Set((existingRows ?? []).map((row) => row.id as string))
    }

    if (posts.length > 0) {
      const { error } = await supabase
        .from("source_posts")
        .upsert(posts.map((post) => ({
          id: post.id,
          persona_id: post.personaId,
          source_type: post.sourceType,
          content: post.content,
          source_url: post.sourceUrl,
          topic: post.topic,
          importance_score: post.importanceScore,
          published_at: post.publishedAt,
          raw_author_username: post.rawAuthorUsername,
          raw_payload: post.rawPayload,
        })), { onConflict: "id" })

      if (error) {
        throw new Error(error.message)
      }
    }

    const inserted = posts.filter((post) => !existingIdSet.has(post.id)).length
    const updated = posts.length - inserted
    const skipped = items.length - posts.length

    return Response.json(
      {
        ok: true,
        actorId: actorResult.actorId,
        matchedAttempt: actorResult.matchedAttempt,
        usernames,
        totalFetched: items.length,
        normalized: posts.length,
        inserted,
        updated,
        skipped,
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
