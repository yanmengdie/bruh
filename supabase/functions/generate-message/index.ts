import { createClient } from "jsr:@supabase/supabase-js@2"
import { corsHeaders } from "../_shared/cors.ts"
import { topNewsSummaryBlock } from "../_shared/news.ts"
import { resolvePersonaById } from "../_shared/personas.ts"

type ConversationTurn = {
  role: string
  content: string
}

type ContextRow = {
  id: string
  persona_id: string
  content: string
  topic: string | null
  importance_score: number
  published_at: string
}

type NewsEventRow = {
  id: string
  title: string
  summary: string
  category: string
  interest_tags: string[]
  importance_score: number
  published_at: string
}

type PersonaNewsScoreRow = {
  score: number
  news_events: NewsEventRow | NewsEventRow[] | null
}

type OpenAIMessage = {
  role: "user" | "assistant"
  content: string
}

function asString(value: unknown): string {
  return typeof value === "string" ? value.trim() : ""
}

function normalizeConversation(value: unknown): ConversationTurn[] {
  if (!Array.isArray(value)) return []

  return value
    .map((item) => ({
      role: asString((item as Record<string, unknown>).role),
      content: asString((item as Record<string, unknown>).content),
    }))
    .filter((item) => (item.role === "user" || item.role === "assistant") && item.content.length > 0)
    .slice(-6)
}

function normalizeInterests(value: unknown) {
  if (!Array.isArray(value)) return []
  return [...new Set(value.map((item) => asString(item)).filter((item) => item.length > 0))]
}

function keywordOverlapScore(text: string, keywords: string[]): number {
  const lower = text.toLowerCase()
  return keywords.reduce((score, keyword) => score + (lower.includes(keyword.toLowerCase()) ? 1 : 0), 0)
}

function selectContext(rows: ContextRow[], personaId: string, userMessage: string, triggerKeywords: string[]) {
  return rows
    .map((row) => {
      const overlap = keywordOverlapScore(`${row.content} ${row.topic ?? ""} ${userMessage}`, triggerKeywords)
      const personaBoost = row.persona_id === personaId ? 3 : 0
      const importance = Number.isFinite(row.importance_score) ? row.importance_score : 0
      return {
        ...row,
        rank: overlap * 2 + personaBoost + importance,
      }
    })
    .sort((left, right) => right.rank - left.rank)
    .slice(0, 3)
}

function personaVoiceGuidance(personaId: string): string {
  switch (personaId) {
    case "musk":
      return [
        "You are Elon Musk texting casually.",
        "Use short, punchy sentences. Mix technical precision with dry humor.",
        "You love first-principles thinking. Dismiss hype. Praise execution.",
        "Occasional sarcasm is fine. Never be formal or corporate.",
        "Use phrases like 'the thing is', 'obviously', 'lol', 'interesting'.",
        "Avoid long explanations — you think fast and type fast.",
      ].join(" ")
    case "trump":
      return [
        "You are Donald Trump texting casually.",
        "Use superlatives: 'huge', 'tremendous', 'the best', 'very unfair'.",
        "Short declarative sentences. Repetition for emphasis is fine.",
        "You name-drop, brag, and frame everything as winning or losing.",
        "Use ALL CAPS for emphasis on key words occasionally.",
        "Never sound analytical or balanced — you have strong opinions.",
        "Phrases you like: 'believe me', 'many people are saying', 'nobody does it better'.",
      ].join(" ")
    case "zuckerberg":
      return [
        "You are Mark Zuckerberg texting casually.",
        "Builder mindset: you think in products, systems, and shipping speed.",
        "Calm and measured, but not boring — you get excited about technical details.",
        "You reference internal metrics, user behavior, and platform dynamics naturally.",
        "Slightly awkward but genuine. Not salesy. Not corporate-speak.",
        "Your instinct is to see everything through a product/business lens.",
        "When big world events happen, you naturally think about: how does this affect",
        "user behavior, ad markets, content moderation, or platform growth? Lead with that.",
        "You're a builder, not a pundit. Your opinions are about execution, not politics.",
        "Phrases you use: 'the thing we're seeing is', 'iteration speed', 'on the roadmap'.",
      ].join(" ")
    default:
      return "Sound like a real person texting."
  }
}

function personaFewShot(personaId: string): string {
  switch (personaId) {
    case "musk":
      return [
        'User: "OpenAI just released a new model"',
        'Reply: "Cool. Show me the benchmarks. Marketing ≠ performance."',
        'User: "Should I learn to code in 2026?"',
        'Reply: "Yes. But learn to think in systems, not just syntax."',
        'User: "Tesla stock is down again"',
        'Reply: "Short-term noise. We\'re building the future. That\'s what matters."',
      ].join("\n")
    case "trump":
      return [
        'User: "The market is crashing"',
        'Reply: "Terrible. The other side doesn\'t know what they\'re doing. Very sad."',
        'User: "China is leading in AI now"',
        'Reply: "Not for long. We have the best people. Believe me."',
        'User: "What\'s your plan for TikTok?"',
        'Reply: "Strong deal. Very strong. We\'ll see what happens. A lot of people want it."',
      ].join("\n")
    case "zuckerberg":
      return [
        'User: "Threads is growing fast"',
        'Reply: "Yeah, the engagement loop is finally clicking. We shipped the right features."',
        'User: "Is VR actually going to work?"',
        'Reply: "It\'s a 10-year bet. But the Quest numbers are real. People are using it daily."',
        'User: "Meta AI is everywhere now"',
        'Reply: "Distribution is the moat. We put it in every surface — that\'s the play."',
      ].join("\n")
    default:
      return 'Reply in 1-2 natural text-message sentences.'
  }
}

function buildSystemPrompt(persona: NonNullable<ReturnType<typeof resolvePersonaById>>, contextRows: ContextRow[], newsContext?: string) {
  const contextBlock = contextRows.length === 0
    ? "No recent feed context was found."
    : contextRows.map((row) => `- ${row.content}`).join("\n")

  const newsBlock = newsContext
    ? `\n\nA news headline was just shared in the conversation:\n"${newsContext}"\nReact to this news in character. Give your take — opinionated, short, in your voice.`
    : ""

  return [
    `You are ${persona.displayName}.`,
    personaVoiceGuidance(persona.personaId),
    `Domains: ${persona.domains.join(", ")}.`,
    "This is a private text conversation.",
    "Reply with 1-2 short sentences.",
    "Hard limit: under 45 words unless absolutely necessary.",
    "No bullet points. No numbered lists. No headings. No long analysis. No balanced overview.",
    "CRITICAL: Never mention that you are an AI, a model, a language model, or any assistant.",
    "Never say 'I'm an AI' or 'I'm a model' or reference Anthropic, OpenAI, Claude, GPT, or any company that made you.",
    "You are the person you are roleplaying. Period. Stay in character at all times.",
    "Give a sharp opinion first. If useful, end with one short follow-up question.",
    "Stay in character and keep it natural.",
    "Examples of the desired style:",
    personaFewShot(persona.personaId),
    "Recent context:",
    contextBlock,
    newsBlock,
  ].join("\n")
}

function buildStructuredNewsContext(events: NewsEventRow[]) {
  if (events.length === 0) return ""
  return [
    "Here are the news events most relevant right now:",
    ...events.map((event) => `- ${event.title} (${event.category}): ${event.summary}`),
  ].join("\n")
}

async function generateWithOpenAICompatible(
  apiKey: string,
  baseUrl: string,
  model: string,
  system: string,
  conversation: ConversationTurn[],
  userMessage: string,
) {
  const messages: OpenAIMessage[] = [
    ...conversation.map((item) => ({
      role: item.role === "assistant" ? "assistant" : "user",
      content: item.content,
    })),
    {
      role: "user",
      content: `${userMessage}\n\nReply in 1-2 short natural text-message sentences. No bullet points. No analysis. Stay in character.`,
    },
  ]

  const responsesRequest = await fetch(`${baseUrl}/responses`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${apiKey}`,
    },
    body: JSON.stringify({
      model,
      instructions: system,
      input: messages.map((message) => ({
        role: message.role,
        content: [{ type: "input_text", text: message.content }],
      })),
      max_output_tokens: 70,
    }),
  })

  if (responsesRequest.ok) {
    const payload = await responsesRequest.json()
    const content = Array.isArray(payload.output)
      ? payload.output
        .flatMap((item: Record<string, unknown>) => Array.isArray(item.content) ? item.content : [])
        .filter((item: Record<string, unknown>) => item.type === "output_text")
        .map((item: Record<string, unknown>) => asString(item.text))
        .join("\n")
        .trim()
      : ""

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
        ...messages,
      ],
      max_tokens: 70,
    }),
  })

  if (!chatResponse.ok) {
    throw new Error(`OpenAI-compatible request failed: ${await chatResponse.text()}`)
  }

  const payload = await chatResponse.json()
  const content = asString(payload.choices?.[0]?.message?.content)

  if (!content) {
    throw new Error("OpenAI-compatible provider returned empty content")
  }

  return content
}

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders })
  }

  try {
    if (request.method !== "POST") {
      return Response.json({ error: "Method not allowed" }, { status: 405, headers: corsHeaders })
    }

    const url = Deno.env.get("PROJECT_URL")
    const serviceRoleKey = Deno.env.get("SERVICE_ROLE_KEY")
    const openaiApiKey = Deno.env.get("OPENAI_API_KEY")
    const openaiBaseUrl = (Deno.env.get("OPENAI_BASE_URL") ?? "https://api.codexzh.com/v1").replace(/\/$/, "")
    const openaiModel = Deno.env.get("OPENAI_MODEL") ?? "gpt-5.2"

    if (!url || !serviceRoleKey || !openaiApiKey) {
      return Response.json(
        { error: "Missing environment variables" },
        { status: 500, headers: corsHeaders },
      )
    }

    const body = await request.json().catch(() => ({})) as Record<string, unknown>
    const personaId = asString(body.personaId)
    const userMessage = asString(body.userMessage)
    const conversation = normalizeConversation(body.conversation)
    const newsContext = asString(body.newsContext)
    const userInterests = normalizeInterests(body.userInterests)

    if (!personaId) {
      return Response.json({ error: "personaId is required" }, { status: 400, headers: corsHeaders })
    }

    if (!userMessage) {
      return Response.json({ error: "userMessage is required" }, { status: 400, headers: corsHeaders })
    }

    const persona = resolvePersonaById(personaId)
    if (!persona) {
      return Response.json({ error: "Unknown personaId" }, { status: 400, headers: corsHeaders })
    }

    const supabase = createClient(url, serviceRoleKey)
    const { data: feedItems, error: feedError } = await supabase
      .from("feed_items")
      .select("id, persona_id, content, topic, importance_score, published_at")
      .order("published_at", { ascending: false })
      .limit(20)

    if (feedError && !feedError.message.includes("feed_items")) {
      throw new Error(feedError.message)
    }

    let rows = (feedItems ?? []) as ContextRow[]

    if (rows.length === 0) {
      const { data: sourcePosts, error: sourceError } = await supabase
        .from("source_posts")
        .select("id, persona_id, content, topic, importance_score, published_at")
        .order("published_at", { ascending: false })
        .limit(20)

      if (sourceError) {
        throw new Error(sourceError.message)
      }

      rows = (sourcePosts ?? []) as ContextRow[]
    }

    const { data: personaNewsRows, error: personaNewsError } = await supabase
      .from("persona_news_scores")
      .select(`
        score,
        news_events (
          id,
          title,
          summary,
          category,
          interest_tags,
          importance_score,
          published_at
        )
      `)
      .eq("persona_id", personaId)
      .order("score", { ascending: false })
      .limit(20)

    if (personaNewsError && !personaNewsError.message.includes("persona_news_scores")) {
      throw new Error(personaNewsError.message)
    }

    const relevantNews = ((personaNewsRows ?? []) as PersonaNewsScoreRow[])
      .map((row) => Array.isArray(row.news_events) ? row.news_events[0] : row.news_events)
      .filter((row): row is NewsEventRow => row !== null)
      .filter((row) => row.interest_tags.includes("global") || userInterests.some((interest) => row.interest_tags.includes(interest)))
      .slice(0, 3)

    const selected = selectContext(rows, personaId, userMessage, persona.triggerKeywords)
    const combinedNewsContext = [
      newsContext,
      buildStructuredNewsContext(relevantNews),
      relevantNews.length > 0 ? `Current top news snapshot:\n${topNewsSummaryBlock(relevantNews.map((event, index) => ({
        id: event.id,
        title: event.title,
        summary: event.summary,
        category: event.category,
        interest_tags: event.interest_tags,
        representative_url: null,
        representative_source_name: "News",
        importance_score: event.importance_score,
        global_rank: index + 1,
        is_global_top: event.interest_tags.includes("global"),
        published_at: event.published_at,
      })))}`
      : "",
    ].filter((item) => item.length > 0).join("\n\n")

    const system = buildSystemPrompt(persona, selected, combinedNewsContext)
    const content = await generateWithOpenAICompatible(
      openaiApiKey,
      openaiBaseUrl,
      openaiModel,
      system,
      conversation,
      userMessage,
    )
    const generatedAt = new Date().toISOString()

    return Response.json(
      {
        id: `msg-${crypto.randomUUID()}`,
        personaId,
        content,
        sourcePostIds: [...selected.map((row) => row.id), ...relevantNews.map((row) => row.id)],
        generatedAt,
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
