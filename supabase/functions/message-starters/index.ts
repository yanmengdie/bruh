import { createClient } from "jsr:@supabase/supabase-js@2"
import { corsHeaders } from "../_shared/cors.ts"
import { asString, defaultStarterMessage, topNewsSummaryBlock } from "../_shared/news.ts"
import { resolvePersonaById } from "../_shared/personas.ts"

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
}

type ScoredEventRow = {
  score: number
  event_id: string
  news_events: StarterEventRow | StarterEventRow[] | null
}

function normalizeInterests(value: unknown) {
  if (!Array.isArray(value)) return []
  return [...new Set(value.map((item) => asString(item)).filter((item) => item.length > 0))]
}

function personaVoicePrompt(personaId: string) {
  switch (personaId) {
    case "musk":
      return "Short, sharp, internet-native, first-principles, slightly sarcastic."
    case "trump":
      return "Bold, headline-first, confident, casual, occasionally emphatic."
    case "zuckerberg":
      return "Builder-minded, calm, product-focused, concise."
    default:
      return "Natural, brief, social."
  }
}

async function generateStarterText(
  apiKey: string | undefined,
  baseUrl: string,
  model: string,
  personaId: string,
  title: string,
  summary: string,
  topSummary: string,
) {
  if (!apiKey) return defaultStarterMessage(personaId, title)

  const persona = resolvePersonaById(personaId)
  if (!persona) return defaultStarterMessage(personaId, title)

  const system = [
    `You are ${persona.displayName}.`,
    personaVoicePrompt(personaId),
    "Write one short incoming text message about a news headline.",
    "1 sentence, max 24 words.",
    "No bullet points. No hashtags. No AI disclaimers.",
    "Sound like a real person texting a friend.",
  ].join(" ")

  const prompt = [
    `Headline: ${title}`,
    `Summary: ${summary}`,
    topSummary ? `Broader top news context:\n${topSummary}` : "",
    "Write the first text you'd send me about this.",
  ].filter((item) => item.length > 0).join("\n\n")

  const response = await fetch(`${baseUrl}/responses`, {
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
      max_output_tokens: 60,
    }),
  })

  if (!response.ok) {
    return defaultStarterMessage(personaId, title)
  }

  const payload = await response.json()
  const content = Array.isArray(payload.output)
    ? payload.output
      .flatMap((item: Record<string, unknown>) => Array.isArray(item.content) ? item.content : [])
      .filter((item: Record<string, unknown>) => item.type === "output_text")
      .map((item: Record<string, unknown>) => asString(item.text))
      .join(" ")
      .trim()
    : ""

  return content || defaultStarterMessage(personaId, title)
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
    const openaiApiKey = Deno.env.get("OPENAI_API_KEY")
    const openaiBaseUrl = (Deno.env.get("OPENAI_BASE_URL") ?? "https://api.codexzh.com/v1").replace(/\/$/, "")
    const openaiModel = Deno.env.get("OPENAI_MODEL") ?? "gpt-5.2"

    if (!projectUrl || !serviceRoleKey) {
      return Response.json({ error: "Missing Supabase environment variables" }, { status: 500, headers: corsHeaders })
    }

    const body = await request.json().catch(() => ({})) as Record<string, unknown>
    const userInterests = normalizeInterests(body.userInterests)
    const personaIds = ["musk", "trump", "zuckerberg"]
    const supabase = createClient(projectUrl, serviceRoleKey)

    const { data: topNewsRows, error: topNewsError } = await supabase
      .from("news_events")
      .select("id, title, summary, category, interest_tags, representative_url, global_rank, is_global_top, published_at")
      .eq("is_global_top", true)
      .order("global_rank", { ascending: true })
      .limit(10)

    if (topNewsError && !topNewsError.message.includes("news_events")) {
      throw new Error(topNewsError.message)
    }

    const topNews = (topNewsRows ?? []) as StarterEventRow[]
    const topSummary = topNewsSummaryBlock(topNews)
    const starters = []

    for (const personaId of personaIds) {
      const { data: scoreRows, error } = await supabase
        .from("persona_news_scores")
        .select(`
          score,
          event_id,
          news_events (
            id,
            title,
            summary,
            category,
            interest_tags,
            representative_url,
            global_rank,
            is_global_top,
            published_at
          )
        `)
        .eq("persona_id", personaId)
        .order("score", { ascending: false })
        .limit(20)

      if (error && !error.message.includes("persona_news_scores")) {
        throw new Error(error.message)
      }

      const relevant = ((scoreRows ?? []) as ScoredEventRow[])
        .map((row) => {
          const event = Array.isArray(row.news_events) ? row.news_events[0] : row.news_events
          return event ? { score: row.score, event } : null
        })
        .filter((row): row is { score: number; event: StarterEventRow } => row !== null)
        .filter((row) =>
          row.event.is_global_top ||
          userInterests.some((interest) => row.event.interest_tags.includes(interest))
        )

      const selected = relevant[0]
        ?? ((scoreRows ?? []) as ScoredEventRow[])
          .map((row) => Array.isArray(row.news_events) ? row.news_events[0] : row.news_events)
          .filter((row): row is StarterEventRow => row !== null)[0]
        ?? topNews[0]
        ?? null
      if (!selected) continue

      const text = await generateStarterText(
        openaiApiKey ?? undefined,
        openaiBaseUrl,
        openaiModel,
        personaId,
        "event" in selected ? selected.event.title : selected.title,
        "event" in selected ? selected.event.summary : selected.summary,
        topSummary,
      )

      const event = "event" in selected ? selected.event : selected
      starters.push({
        id: `starter-news-${personaId}-${event.id}`,
        personaId,
        text,
        sourcePostIds: [event.id],
        createdAt: event.published_at,
        category: event.category,
        headline: event.title,
        articleUrl: event.representative_url,
        isGlobalTop: event.is_global_top,
      })
    }

    return Response.json({ starters, topSummary }, { headers: corsHeaders })
  } catch (error) {
    return Response.json(
      { error: error instanceof Error ? error.message : "Unknown error" },
      { status: 500, headers: corsHeaders },
    )
  }
})
