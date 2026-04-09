import { personaMap, resolvePersonaById } from "./personas.ts"

export type FeedDefinition = {
  slug: string
  url: string
  sourceName: string
  category: string
}

export type ParsedNewsArticle = {
  id: string
  sourceName: string
  sourceType: string
  feedSlug: string
  title: string
  summary: string
  articleUrl: string
  category: string
  interestTags: string[]
  publishedAt: string
  importanceScore: number
  rawPayload: Record<string, unknown>
}

export type NewsEventRow = {
  id: string
  title: string
  summary: string
  category: string
  interest_tags: string[]
  representative_url: string | null
  representative_source_name: string
  importance_score: number
  global_rank: number | null
  is_global_top: boolean
  published_at: string
}

const stopWords = new Set([
  "a", "an", "and", "are", "as", "at", "be", "by", "for", "from",
  "in", "into", "is", "it", "of", "on", "or", "that", "the", "to",
  "with", "after", "amid", "over", "under", "up", "down",
])

const entityKeywords: Record<string, string[]> = Object.fromEntries(
  Object.values(personaMap).map((persona) => [persona.personaId, persona.entityKeywords]),
)

export const defaultNewsFeeds: FeedDefinition[] = [
  {
    slug: "bbc-politics",
    url: "https://feeds.bbci.co.uk/news/politics/rss.xml",
    sourceName: "BBC",
    category: "politics",
  },
  {
    slug: "bbc-business",
    url: "https://feeds.bbci.co.uk/news/business/rss.xml",
    sourceName: "BBC",
    category: "finance",
  },
  {
    slug: "bbc-technology",
    url: "https://feeds.bbci.co.uk/news/technology/rss.xml",
    sourceName: "BBC",
    category: "tech",
  },
  {
    slug: "bbc-world",
    url: "https://feeds.bbci.co.uk/news/world/rss.xml",
    sourceName: "BBC",
    category: "world",
  },
]

export function asString(value: unknown): string {
  return typeof value === "string" ? value.trim() : ""
}

export function stableHash(value: string) {
  let hash = 5381
  for (const char of value) {
    hash = ((hash << 5) + hash) ^ char.charCodeAt(0)
  }
  return (hash >>> 0).toString(16)
}

export function decodeHtmlEntities(value: string) {
  return value
    .replace(/<!\[CDATA\[(.*?)\]\]>/gs, "$1")
    .replace(/&amp;/g, "&")
    .replace(/&quot;/g, "\"")
    .replace(/&#39;/g, "'")
    .replace(/&apos;/g, "'")
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">")
    .replace(/&nbsp;/g, " ")
}

export function stripHtml(value: string) {
  return decodeHtmlEntities(value)
    .replace(/<[^>]+>/g, " ")
    .replace(/\s+/g, " ")
    .trim()
}

export function extractTag(block: string, tag: string) {
  const match = block.match(new RegExp(`<${tag}[^>]*>([\\s\\S]*?)<\\/${tag}>`, "i"))
  return match ? stripHtml(match[1]) : ""
}

export function parseRssItems(xml: string) {
  const normalized = decodeHtmlEntities(xml)
  return [...normalized.matchAll(/<item\b[\s\S]*?>([\s\S]*?)<\/item>/gi)].map((match) => {
    const item = match[1]
    const title = extractTag(item, "title")
    const link = extractTag(item, "link")
    const guid = extractTag(item, "guid")
    const description = extractTag(item, "description")
    const pubDate = extractTag(item, "pubDate")
    return { title, link, guid, description, pubDate }
  })
}

export function normalizeHeadline(value: string) {
  return value
    .toLowerCase()
    .replace(/\s*[-–|:]\s*bbc.*$/i, "")
    .replace(/[^a-z0-9\s]/g, " ")
    .split(/\s+/)
    .filter((token) => token.length > 1 && !stopWords.has(token))
    .slice(0, 8)
    .join(" ")
}

export function inferInterestTags(text: string, category: string) {
  const lower = `${category} ${text}`.toLowerCase()
  const tags = new Set<string>(["global", category])

  if (category === "politics") tags.add("politics")
  if (["finance"].includes(category) || /\b(market|markets|stock|stocks|trade|economy|fed|bank|banks|tariff|tariffs)\b/.test(lower)) tags.add("finance")
  if (["tech"].includes(category) || /\b(ai|tech|software|meta|tesla|spacex|xai|openai|chip|chips|semiconductor|semiconductors)\b/.test(lower)) tags.add("tech")
  if (/\b(china|beijing|shanghai)\b/.test(lower)) tags.add("china")
  if (/\b(war|ukraine|russia|middle east|taiwan|nato|election|congress|government|white house)\b/.test(lower)) tags.add("politics")
  if (/\b(social|threads|instagram|facebook|tiktok|xiaohongshu)\b/.test(lower)) tags.add("social")

  return [...tags]
}

export function scoreNewsRecency(publishedAt: string) {
  const ageHours = Math.max((Date.now() - Date.parse(publishedAt)) / (1000 * 60 * 60), 0)
  if (ageHours <= 6) return 2.2
  if (ageHours <= 24) return 1.5
  if (ageHours <= 48) return 1.0
  return 0.4
}

export function buildEventKey(title: string, category: string) {
  const normalized = normalizeHeadline(title)
  return `${category}:${normalized || stableHash(title.toLowerCase()).slice(0, 10)}`
}

export function scorePersonaForEvent(personaId: string, title: string, summary: string, interestTags: string[]) {
  const persona = resolvePersonaById(personaId)
  if (!persona) {
    return { score: 0, reasonCodes: [] as string[], matchedInterests: [] as string[] }
  }

  const lower = `${title} ${summary}`.toLowerCase()
  const reasonCodes: string[] = []
  const matchedInterests = interestTags.filter((tag) => persona.domains.includes(tag))
  let score = 0

  for (const domain of persona.domains) {
    if (interestTags.includes(domain)) {
      score += 2.5
      reasonCodes.push("domain_match")
    }
  }

  for (const keyword of persona.triggerKeywords) {
    if (lower.includes(keyword.toLowerCase())) {
      score += 1.8
      reasonCodes.push("keyword_hit")
    }
  }

  for (const keyword of entityKeywords[personaId] ?? []) {
    if (lower.includes(keyword.toLowerCase())) {
      score += 3.2
      reasonCodes.push("entity_hit")
    }
  }

  if (interestTags.includes("global")) {
    score += 0.8
    reasonCodes.push("global_top")
  }

  return {
    score,
    reasonCodes: [...new Set(reasonCodes)],
    matchedInterests: [...new Set(matchedInterests)],
  }
}

export function categorizeFeedScore(category: string) {
  switch (category) {
    case "politics":
      return 1.4
    case "finance":
      return 1.2
    case "tech":
      return 1.1
    default:
      return 0.9
  }
}

export function parseFeedsFromBody(body: Record<string, unknown>) {
  const customFeeds = Array.isArray(body.feeds) ? body.feeds : []
  if (customFeeds.length === 0) return defaultNewsFeeds

  const parsed = customFeeds
    .map((item) => {
      const row = item as Record<string, unknown>
      const slug = asString(row.slug)
      const url = asString(row.url)
      const sourceName = asString(row.sourceName)
      const category = asString(row.category)
      if (!slug || !url || !sourceName || !category) return null
      return { slug, url, sourceName, category }
    })
    .filter((item): item is FeedDefinition => item !== null)

  return parsed.length > 0 ? parsed : defaultNewsFeeds
}

export function topNewsSummaryBlock(events: NewsEventRow[]) {
  if (events.length === 0) return ""
  return events
    .map((event, index) => {
      const rank = event.global_rank ?? index + 1
      const tags = event.interest_tags.filter((tag) => tag !== "global").join(", ")
      return `#${rank} ${event.title}${tags ? ` [${tags}]` : ""}`
    })
    .join("\n")
}

export function defaultStarterMessage(personaId: string, title: string) {
  switch (personaId) {
    case "musk":
      return `${title} and people still focus on the surface instead of the underlying system.`
    case "trump":
      return `${title} is what weak leadership looks like when a problem gets completely out of hand.`
    case "sam_altman":
      return `${title} matters because it changes what AI products are actually possible in the next cycle.`
    case "zhang_peng":
      return `${title} 不是一条普通新闻，更像是技术周期又往前走了一格。`
    case "lei_jun":
      return `${title} 背后一定不只是热度，产品、供应链和节奏都在一起变化。`
    case "liu_jingkang":
      return `${title} 这种消息我会先看它到底解决了什么真实用户问题。`
    case "luo_yonghao":
      return `${title} 听着像新闻，实际上更值得看的是它到底有没有把事做对。`
    case "justin_sun":
      return `${title} is the kind of move that changes sentiment before most people price it in.`
    case "kim_kardashian":
      return `${title} is not just a headline. It is a culture-and-brand signal if you read it correctly.`
    case "papi":
      return `${title} 这种事我第一反应不是热度，而是大家到底在情绪上共鸣了什么。`
    case "kobe_bryant":
      return `${title} is about standards. Pressure only exposes whether the work was really there.`
    case "cristiano_ronaldo":
      return `${title} is the kind of moment where mentality, discipline, and pressure decide everything.`
    default:
      return title
  }
}

export function allPersonaIds() {
  return Object.values(personaMap).map((persona) => persona.personaId)
}
