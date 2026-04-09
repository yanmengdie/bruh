import { createClient } from "jsr:@supabase/supabase-js@2"
import { corsHeaders } from "../_shared/cors.ts"
import { allPersonaIds, asString, defaultStarterMessage, topNewsSummaryBlock } from "../_shared/news.ts"
import { resolvePersonaById } from "../_shared/personas.ts"
import { personaFewShotExamples, personaImageStyle, personaRolePrompt } from "../_shared/persona_skills.ts"

type StarterEventRow = {
  id: string
  title: string
  summary: string
  category: string
  interest_tags: string[]
  representative_url: string | null
  global_rank: number | null
  is_global_top: boolean
  published_at: string
  importance_score: number
}

type PersonaScoreRow = {
  event_id: string
  persona_id: string
  score: number
  reason_codes: string[] | null
  matched_interests: string[] | null
}

type CandidateStarter = {
  event: StarterEventRow
  score: number
  selectionReasons: string[]
}

type SelectedStarter = {
  event: StarterEventRow
  personaId: string
  score: number
  selectionReasons: string[]
}

function clamp(value: number, min: number, max: number) {
  return Math.min(max, Math.max(min, value))
}

function hashString(value: string) {
  let hash = 2166136261

  for (let index = 0; index < value.length; index += 1) {
    hash ^= value.charCodeAt(index)
    hash = Math.imul(hash, 16777619)
  }

  return hash >>> 0
}

function seededUnitInterval(seed: string) {
  return hashString(seed) / 4294967295
}

function normalizeInterests(value: unknown) {
  if (!Array.isArray(value)) return []
  return [...new Set(value.map((item) => asString(item)).filter((item) => item.length > 0))]
}

function normalizeStringArray(value: unknown) {
  if (!Array.isArray(value)) return []
  return [...new Set(value.map((item) => asString(item)).filter((item) => item.length > 0))]
}

function cleanStarterText(text: string) {
  return text
    .split("\n")
    .map((line) => line.trim())
    .filter((line) => {
      const lower = line.toLowerCase()
      if (!lower) return false
      return ![
        "i'm kiro",
        "i am kiro",
        "i'm an ai assistant",
        "i am an ai assistant",
        "i don't roleplay",
        "i do not roleplay",
        "i can't discuss that",
        "i cannot discuss that",
      ].some((prefix) => lower.startsWith(prefix))
    })
    .join(" ")
    .replace(/\s+/g, " ")
    .trim()
}

function personaVisualShareBase(
  persona: NonNullable<ReturnType<typeof resolvePersonaById>>,
) {
  let probability = 0.12
  const domains = new Set(persona.domains)

  if (domains.has("entertainment")) probability += 0.14
  if (domains.has("sports")) probability += 0.1
  if (domains.has("creator")) probability += 0.08
  if (domains.has("world")) probability += 0.06
  if (domains.has("business")) probability += 0.04

  switch (persona.personaId) {
    case "trump":
    case "kim_kardashian":
    case "kobe_bryant":
    case "cristiano_ronaldo":
    case "musk":
    case "justin_sun":
      probability += 0.08
      break
    case "sam_altman":
    case "zhang_peng":
    case "liu_jingkang":
      probability -= 0.03
      break
    default:
      break
  }

  return clamp(probability, 0.08, 0.52)
}

function personaSourceShareBase(
  persona: NonNullable<ReturnType<typeof resolvePersonaById>>,
) {
  let probability = 0.14
  const domains = new Set(persona.domains)

  if (domains.has("world")) probability += 0.14
  if (domains.has("business")) probability += 0.08
  if (domains.has("technology")) probability += 0.08
  if (domains.has("ai")) probability += 0.08
  if (domains.has("entertainment")) probability -= 0.02
  if (domains.has("sports")) probability -= 0.02

  switch (persona.personaId) {
    case "sam_altman":
    case "zhang_peng":
    case "liu_jingkang":
      probability += 0.14
      break
    case "musk":
    case "trump":
    case "lei_jun":
    case "luo_yonghao":
      probability += 0.08
      break
    case "kim_kardashian":
    case "papi":
    case "kobe_bryant":
    case "cristiano_ronaldo":
      probability -= 0.04
      break
    default:
      break
  }

  return clamp(probability, 0.08, 0.58)
}

function starterImageProbability(
  persona: NonNullable<ReturnType<typeof resolvePersonaById>>,
  item: SelectedStarter,
) {
  let probability = personaVisualShareBase(persona)

  if (item.selectionReasons.includes("persona_related")) probability += 0.12
  if (item.selectionReasons.includes("global_top")) probability += 0.06
  if (item.event.is_global_top) probability += 0.06
  if (item.event.representative_url) probability += 0.04

  switch (item.event.category) {
    case "sports":
    case "entertainment":
    case "world":
      probability += 0.08
      break
    case "technology":
    case "business":
    case "ai":
    case "crypto":
      probability += 0.04
      break
    default:
      break
  }

  return clamp(probability, 0.08, 0.68)
}

function pickStarterImageEventIds(selected: SelectedStarter[]) {
  const ranked = selected
    .map((item) => {
      const persona = resolvePersonaById(item.personaId)
      if (!persona) return null

      const probability = starterImageProbability(persona, item)
      const randomness = seededUnitInterval(`starter-image:${item.personaId}:${item.event.id}:v1`)

      if (randomness >= probability) return null

      return {
        eventId: item.event.id,
        personaId: item.personaId,
        priority:
          probability - randomness +
          (item.selectionReasons.includes("persona_related") ? 0.08 : 0) +
          (item.event.is_global_top ? 0.04 : 0),
      }
    })
    .filter((candidate): candidate is { eventId: string; personaId: string; priority: number } => candidate !== null)
    .sort((left, right) => right.priority - left.priority || left.personaId.localeCompare(right.personaId))

  const eventIds = new Set<string>()
  const seenPersonaIds = new Set<string>()

  for (const candidate of ranked) {
    if (seenPersonaIds.has(candidate.personaId)) continue
    eventIds.add(candidate.eventId)
    seenPersonaIds.add(candidate.personaId)
    if (eventIds.size >= 1) break
  }

  return eventIds
}

function resolveStarterSourceUrl(
  persona: NonNullable<ReturnType<typeof resolvePersonaById>>,
  item: CandidateStarter,
) {
  const url = asString(item.event.representative_url)
  if (!url) return null

  let probability = personaSourceShareBase(persona)
  if (item.selectionReasons.includes("global_top")) probability += 0.08
  if (item.selectionReasons.includes("persona_related")) probability += 0.06
  if (item.event.is_global_top) probability += 0.04

  switch (item.event.category) {
    case "world":
    case "business":
    case "technology":
    case "ai":
    case "crypto":
      probability += 0.08
      break
    case "sports":
    case "entertainment":
      probability -= 0.02
      break
    default:
      break
  }

  const randomness = seededUnitInterval(`starter-source:${persona.personaId}:${item.event.id}:v1`)
  return randomness < clamp(probability, 0.08, 0.76) ? url : null
}

function extractImageUrl(payload: Record<string, unknown>) {
  const collectionCandidates = [payload.data, payload.images, payload.output, payload.results]

  for (const candidate of collectionCandidates) {
    if (!Array.isArray(candidate)) continue

    for (const item of candidate) {
      const row = item as Record<string, unknown>
      const imageUrl = asString(row.url ?? row.image_url ?? row.imageUrl)
      if (imageUrl) return imageUrl
    }
  }

  return asString(payload.url ?? payload.image_url ?? payload.imageUrl)
}

function buildStarterImagePrompt(
  persona: NonNullable<ReturnType<typeof resolvePersonaById>>,
  item: CandidateStarter,
  starterText: string,
) {
  return [
    `Create the image ${persona.displayName} would casually attach while texting a friend about this news.`,
    "This is a contextual image attached to a chat message, not a UI screenshot, not a meme template, and not a poster.",
    `Persona visual taste: ${personaImageStyle(persona.personaId)}`,
    `Message text: ${starterText}`,
    `Headline: ${item.event.title}`,
    `Summary: ${item.event.summary}`,
    `Category: ${item.event.category}`,
    "Show one concrete real-world scene, object, location, or moment implied by the message and the news.",
    "If the message implies a place, meeting, stage, locker room, office, arena, rally, product, or travel scene, visualize that directly.",
    "Prefer a candid editorial or documentary feel over generic concept art.",
    "No text overlays, captions, watermarks, screenshots, phone frames, chat bubbles, or split panels.",
  ].join("\n\n")
}

async function generateStarterImageWithNanoBanana(
  apiKey: string,
  baseUrl: string,
  model: string,
  prompt: string,
) {
  const response = await fetch(`${baseUrl}/images/generations`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${apiKey}`,
    },
    body: JSON.stringify({
      model,
      prompt,
      aspect_ratio: "1:1",
      image_size: "1k",
      response_format: "url",
    }),
    signal: AbortSignal.timeout(12_000),
  })

  if (!response.ok) {
    throw new Error(`Nano Banana request failed: ${await response.text()}`)
  }

  const payload = await response.json()
  const imageUrl = extractImageUrl(payload)
  if (!imageUrl) {
    throw new Error("Nano Banana returned no image URL")
  }

  return imageUrl
}

async function maybeGenerateStarterImage(
  nanoBananaApiKey: string | undefined,
  nanoBananaBaseUrl: string,
  nanoBananaModel: string,
  personaId: string,
  item: CandidateStarter,
  starterText: string,
) {
  const persona = resolvePersonaById(personaId)
  if (!persona) return null

  if (!nanoBananaApiKey) {
    return null
  }

  try {
    return await generateStarterImageWithNanoBanana(
      nanoBananaApiKey,
      nanoBananaBaseUrl,
      nanoBananaModel,
      buildStarterImagePrompt(persona, item, starterText),
    )
  } catch (_) {
    return null
  }
}

function pickPersonaForEvent(scores: PersonaScoreRow[], selectionReasons: string[]) {
  let ranked = scores

  if (selectionReasons.includes("persona_related")) {
    const entityHitRows = scores.filter((row) => normalizeStringArray(row.reason_codes).includes("entity_hit"))
    if (entityHitRows.length > 0) {
      ranked = entityHitRows
    }
  }

  return ranked
    .slice()
    .sort((left, right) => right.score - left.score || left.persona_id.localeCompare(right.persona_id))[0] ?? null
}

function collectSelectedStarters(
  events: StarterEventRow[],
  scoresByEvent: Map<string, PersonaScoreRow[]>,
  userInterests: string[],
) {
  const reasonsByEvent = new Map<string, Set<string>>()

  const globalEvents = events
    .filter((event) => event.is_global_top)
    .sort((left, right) => (left.global_rank ?? 999) - (right.global_rank ?? 999))
    .slice(0, 10)

  for (const event of globalEvents) {
    const reasons = reasonsByEvent.get(event.id) ?? new Set<string>()
    reasons.add("global_top")
    reasonsByEvent.set(event.id, reasons)
  }

  if (userInterests.length > 0) {
    const interestEvents = events
      .filter((event) => !event.is_global_top && userInterests.includes(event.category))
      .sort((left, right) =>
        right.importance_score - left.importance_score ||
        Date.parse(right.published_at) - Date.parse(left.published_at)
      )
      .slice(0, 10)

    for (const event of interestEvents) {
      const reasons = reasonsByEvent.get(event.id) ?? new Set<string>()
      reasons.add("interest_match")
      reasonsByEvent.set(event.id, reasons)
    }
  }

  const personaRelatedEvents = events.filter((event) =>
    (scoresByEvent.get(event.id) ?? []).some((row) => normalizeStringArray(row.reason_codes).includes("entity_hit"))
  )

  for (const event of personaRelatedEvents) {
    const reasons = reasonsByEvent.get(event.id) ?? new Set<string>()
    reasons.add("persona_related")
    reasonsByEvent.set(event.id, reasons)
  }

  const selected: SelectedStarter[] = []

  for (const event of events) {
    const selectionReasons = [...(reasonsByEvent.get(event.id) ?? new Set<string>())]
    if (selectionReasons.length === 0) continue

    const scores = scoresByEvent.get(event.id) ?? []
    const pickedScore = pickPersonaForEvent(scores, selectionReasons)
    if (!pickedScore) continue

    selected.push({
      event,
      personaId: pickedScore.persona_id,
      score: pickedScore.score,
      selectionReasons,
    })
  }

  if (selected.length > 0) {
    return selected.sort((left, right) =>
      Date.parse(left.event.published_at) - Date.parse(right.event.published_at) ||
      (left.event.global_rank ?? 999) - (right.event.global_rank ?? 999) ||
      left.personaId.localeCompare(right.personaId)
    )
  }

  const fallbackEvent = events.find((event) => event.is_global_top) ?? events[0] ?? null
  if (!fallbackEvent) return []

  const fallbackScore = pickPersonaForEvent(scoresByEvent.get(fallbackEvent.id) ?? [], ["fallback_global_top"])
  if (!fallbackScore) return []

  return [{
    event: fallbackEvent,
    personaId: fallbackScore.persona_id,
    score: fallbackScore.score,
    selectionReasons: ["fallback_global_top"],
  }]
}

async function generateSingleStarterText(
  anthropicApiKey: string | undefined,
  anthropicBaseUrl: string,
  anthropicModel: string,
  personaId: string,
  item: CandidateStarter,
  topSummary: string,
) {
  const fallback = defaultStarterMessage(personaId, item.event.title)
  const persona = resolvePersonaById(personaId)
  if (!persona) return fallback

  const system = [
    `You are ${persona.displayName}.`,
    personaRolePrompt(personaId),
    "Reply like a real person texting a friend about a piece of news.",
    "Exactly 1 sentence, max 24 words.",
    "Lead with your take, not a summary.",
    "Avoid phrases like 'big story today', 'huge headline today', 'worth watching', or 'worth noting'.",
    "No bullet points. No hashtags. No AI disclaimers.",
    "Examples of the desired style:",
    personaFewShotExamples(personaId),
  ].join(" ")

  const prompt = [
    `Headline: ${item.event.title}`,
    `Summary: ${item.event.summary}`,
    `Category: ${item.event.category}`,
    `Why this was selected: ${item.selectionReasons.join(", ")}`,
    topSummary ? `Broader top news context:\n${topSummary}` : "",
    "Write the first text you'd send me about this.",
  ].filter((value) => value.length > 0).join("\n\n")

  if (anthropicApiKey) {
    const anthropicResponse = await fetch(`${anthropicBaseUrl}/v1/messages`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "x-api-key": anthropicApiKey,
        "anthropic-version": "2023-06-01",
      },
      body: JSON.stringify({
        model: anthropicModel,
        max_tokens: 120,
        temperature: 0.4,
        system,
        messages: [{
          role: "user",
          content: prompt,
        }],
      }),
    })

    if (anthropicResponse.ok) {
      const payload = await anthropicResponse.json()
      const content = Array.isArray(payload.content)
        ? payload.content
          .filter((block: Record<string, unknown>) => block.type === "text")
          .map((block: Record<string, unknown>) => asString(block.text))
          .join(" ")
          .trim()
        : ""

      const cleaned = cleanStarterText(content)
      if (cleaned) {
        return cleaned
      }
    }
  }

  return fallback
}

async function generateStarterTexts(
  anthropicApiKey: string | undefined,
  anthropicBaseUrl: string,
  anthropicModel: string,
  personaId: string,
  items: CandidateStarter[],
  topSummary: string,
) {
  if (items.length === 0) return new Map<string, string>()

  const fallbackTexts = new Map(items.map((item) => [item.event.id, defaultStarterMessage(personaId, item.event.title)]))
  if (!anthropicApiKey) return fallbackTexts

  const generatedEntries = await Promise.all(items.map(async (item) => [
    item.event.id,
    await generateSingleStarterText(anthropicApiKey, anthropicBaseUrl, anthropicModel, personaId, item, topSummary),
  ] as const))

  return new Map(generatedEntries)
}

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
    const anthropicApiKey = Deno.env.get("ANTHROPIC_API_KEY")
    const anthropicBaseUrl = (Deno.env.get("ANTHROPIC_BASE_URL") ?? "https://api.anthropic.com").replace(/\/$/, "")
    const anthropicModel = Deno.env.get("ANTHROPIC_MODEL") ?? "claude-sonnet-4-5-20250929"
    const nanoBananaApiKey = Deno.env.get("NANO_BANANA_API_KEY")
    const nanoBananaBaseUrl = (Deno.env.get("NANO_BANANA_BASE_URL") ?? "https://ccodezh.com/v1").replace(/\/$/, "")
    const nanoBananaModel = Deno.env.get("NANO_BANANA_MODEL") ?? "nano-banana"

    if (!projectUrl || !serviceRoleKey) {
      return Response.json({ error: "Missing Supabase environment variables" }, { status: 500, headers: corsHeaders })
    }

    const body = await request.json().catch(() => ({})) as Record<string, unknown>
    const userInterests = normalizeInterests(body.userInterests)
    const supabase = createClient(projectUrl, serviceRoleKey)

    const { data: eventRows, error: eventError } = await supabase
      .from("news_events")
      .select("id, title, summary, category, interest_tags, representative_url, global_rank, is_global_top, published_at, importance_score")
      .order("is_global_top", { ascending: false })
      .order("global_rank", { ascending: true, nullsFirst: false })
      .order("importance_score", { ascending: false })
      .limit(30)

    if (eventError && !eventError.message.includes("news_events")) {
      throw new Error(eventError.message)
    }

    const events = (eventRows ?? []) as StarterEventRow[]
    const topNews = events
      .filter((event) => event.is_global_top)
      .sort((left, right) => (left.global_rank ?? 999) - (right.global_rank ?? 999))

    const topSummary = topNewsSummaryBlock(topNews)
    if (events.length === 0) {
      return Response.json({ starters: [], topSummary }, { headers: corsHeaders })
    }

    const { data: scoreRows, error: scoreError } = await supabase
      .from("persona_news_scores")
      .select("event_id, persona_id, score, reason_codes, matched_interests")
      .in("event_id", events.map((event) => event.id))
      .in("persona_id", allPersonaIds())

    if (scoreError && !scoreError.message.includes("persona_news_scores")) {
      throw new Error(scoreError.message)
    }

    const scoresByEvent = new Map<string, PersonaScoreRow[]>()
    for (const row of (scoreRows ?? []) as PersonaScoreRow[]) {
      const bucket = scoresByEvent.get(row.event_id) ?? []
      bucket.push(row)
      scoresByEvent.set(row.event_id, bucket)
    }

    const selected = collectSelectedStarters(events, scoresByEvent, userInterests)
    const selectedStarterImageEventIds = pickStarterImageEventIds(selected)
    const starters = []

    for (const personaId of [...new Set(selected.map((item) => item.personaId))].sort()) {
      const items = selected
        .filter((item) => item.personaId == personaId)
        .sort((left, right) => Date.parse(left.event.published_at) - Date.parse(right.event.published_at))
        .map((item) => ({
          event: item.event,
          score: item.score,
          selectionReasons: item.selectionReasons,
        }))

      const generatedTexts = await generateStarterTexts(
        anthropicApiKey ?? undefined,
        anthropicBaseUrl,
        anthropicModel,
        personaId,
        items,
        topSummary,
      )
      const generatedImages = new Map(await Promise.all(
        items
          .filter((item) => selectedStarterImageEventIds.has(item.event.id))
          .map(async (item) => [
            item.event.id,
            await maybeGenerateStarterImage(
              nanoBananaApiKey ?? undefined,
              nanoBananaBaseUrl,
              nanoBananaModel,
              personaId,
              item,
              generatedTexts.get(item.event.id) ?? defaultStarterMessage(personaId, item.event.title),
            ),
          ] as const),
      ))

      for (const item of items) {
        const persona = resolvePersonaById(personaId)
        const sourceUrl = persona ? resolveStarterSourceUrl(persona, item) : null
        starters.push({
          id: `starter-news-${personaId}-${item.event.id}`,
          personaId,
          text: generatedTexts.get(item.event.id) ?? defaultStarterMessage(personaId, item.event.title),
          imageUrl: generatedImages.get(item.event.id) ?? null,
          sourceUrl,
          sourcePostIds: [item.event.id],
          createdAt: item.event.published_at,
          category: item.event.category,
          headline: item.event.title,
          isGlobalTop: item.event.is_global_top,
          selectionReasons: item.selectionReasons,
        })
      }
    }

    starters.sort((left, right) =>
      left.personaId.localeCompare(right.personaId) ||
      Date.parse(left.createdAt) - Date.parse(right.createdAt)
    )

    return Response.json({ starters, topSummary }, { headers: corsHeaders })
  } catch (error) {
    return Response.json(
      { error: error instanceof Error ? error.message : "Unknown error" },
      { status: 500, headers: corsHeaders },
    )
  }
})
