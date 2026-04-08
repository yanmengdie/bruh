import { createClient } from "jsr:@supabase/supabase-js@2"
import { corsHeaders } from "../_shared/cors.ts"
import { allPersonaIds, asString, defaultStarterMessage, topNewsSummaryBlock } from "../_shared/news.ts"
import { resolvePersonaById } from "../_shared/personas.ts"
import { personaFewShotExamples, personaRolePrompt } from "../_shared/persona_skills.ts"

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

function normalizeInterests(value: unknown) {
  if (!Array.isArray(value)) return []
  return [...new Set(value.map((item) => asString(item)).filter((item) => item.length > 0))]
}

function normalizeStringArray(value: unknown) {
  if (!Array.isArray(value)) return []
  return [...new Set(value.map((item) => asString(item)).filter((item) => item.length > 0))]
}

function extractOutputText(payload: Record<string, unknown>) {
  return Array.isArray(payload.output)
    ? payload.output
      .flatMap((item: Record<string, unknown>) => Array.isArray(item.content) ? item.content : [])
      .filter((item: Record<string, unknown>) => item.type === "output_text")
      .map((item: Record<string, unknown>) => asString(item.text))
      .join(" ")
      .trim()
    : ""
}

function stripCodeFence(value: string) {
  const trimmed = value.trim()
  if (!trimmed.startsWith("```")) return trimmed
  return trimmed
    .replace(/^```[a-zA-Z0-9_-]*\s*/, "")
    .replace(/\s*```$/, "")
    .trim()
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
  apiKey: string | undefined,
  baseUrl: string,
  model: string,
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

  if (!apiKey) {
    return fallback
  }

  const responsesRequest = await fetch(`${baseUrl}/responses`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${apiKey}`,
    },
    body: JSON.stringify({
      model,
      instructions: system,
      input: [{
        role: "user",
        content: [{ type: "input_text", text: prompt }],
      }],
      max_output_tokens: 80,
    }),
  })

  if (responsesRequest.ok) {
    const payload = await responsesRequest.json()
    const content = cleanStarterText(stripCodeFence(extractOutputText(payload)))
    if (content) {
      return content
    }
  }

  const chatResponse = await fetch(`${baseUrl}/chat/completions`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${apiKey}`,
    },
    body: JSON.stringify({
      model,
      messages: [
        { role: "system", content: system },
        { role: "user", content: prompt },
      ],
      max_tokens: 80,
    }),
  })

  if (!chatResponse.ok) {
    return fallback
  }

  const chatPayload = await chatResponse.json()
  const content = cleanStarterText(asString(chatPayload.choices?.[0]?.message?.content))
  return content || fallback
}

async function generateStarterTexts(
  anthropicApiKey: string | undefined,
  anthropicBaseUrl: string,
  anthropicModel: string,
  apiKey: string | undefined,
  baseUrl: string,
  model: string,
  personaId: string,
  items: CandidateStarter[],
  topSummary: string,
) {
  if (items.length === 0) return new Map<string, string>()

  const fallbackTexts = new Map(items.map((item) => [item.event.id, defaultStarterMessage(personaId, item.event.title)]))
  if (!anthropicApiKey && !apiKey) return fallbackTexts

  const generatedEntries = await Promise.all(items.map(async (item) => [
    item.event.id,
    (anthropicApiKey || apiKey)
      ? await generateSingleStarterText(anthropicApiKey, anthropicBaseUrl, anthropicModel, apiKey, baseUrl, model, personaId, item, topSummary)
      : fallbackTexts.get(item.event.id) ?? defaultStarterMessage(personaId, item.event.title),
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
    const openaiApiKey = Deno.env.get("OPENAI_API_KEY")
    const openaiBaseUrl = (Deno.env.get("OPENAI_BASE_URL") ?? "https://api.codexzh.com/v1").replace(/\/$/, "")
    const openaiModel = Deno.env.get("OPENAI_MODEL") ?? "gpt-5.2"

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
        openaiApiKey ?? undefined,
        openaiBaseUrl,
        openaiModel,
        personaId,
        items,
        topSummary,
      )

      for (const item of items) {
        starters.push({
          id: `starter-news-${personaId}-${item.event.id}`,
          personaId,
          text: generatedTexts.get(item.event.id) ?? defaultStarterMessage(personaId, item.event.title),
          sourcePostIds: [item.event.id],
          createdAt: item.event.published_at,
          category: item.event.category,
          headline: item.event.title,
          articleUrl: item.event.representative_url,
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
