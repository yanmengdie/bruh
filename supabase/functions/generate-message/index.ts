import { createClient } from "jsr:@supabase/supabase-js@2"
import { corsHeaders } from "../_shared/cors.ts"
import { topNewsSummaryBlock } from "../_shared/news.ts"
import { resolvePersonaById } from "../_shared/personas.ts"
import { personaFewShotExamples, personaImageStyle, personaRolePrompt } from "../_shared/persona_skills.ts"

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

function buildSystemPrompt(
  persona: NonNullable<ReturnType<typeof resolvePersonaById>>,
  contextRows: ContextRow[],
  newsContext: string | undefined,
  requestImage: boolean,
) {
  const contextBlock = contextRows.length === 0
    ? "No recent feed context was found."
    : contextRows.map((row) => `- ${row.content}`).join("\n")

  const newsBlock = newsContext
    ? `\n\nA news headline was just shared in the conversation:\n"${newsContext}"\nReact to this news in character. Give your take — opinionated, short, in your voice.`
    : ""

  const base = [
    "You are the persona described below.",
    personaRolePrompt(persona.personaId),
    "Your voice must be unmistakable and consistent with the persona description. If it could be said by a generic assistant, it's wrong.",
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
    personaFewShotExamples(persona.personaId),
    "Recent context:",
    contextBlock,
    newsBlock,
  ]

  if (requestImage) {
    base.push(
      "An image will be generated for this message.",
      "Do not say you cannot generate images or mention prompts or tools.",
      "If you add text, keep it to one short in-character sentence.",
    )
  }

  return base.join("\n")
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
  styleGuide: string,
  conversation: ConversationTurn[],
  userMessage: string,
) {
  const userInstruction = [
    "STYLE GUIDE (mandatory):",
    styleGuide,
    "Use the persona's voice and signature cadence.",
    "Do not mention being an AI or assistant.",
  ].join("\n")

  const messages: OpenAIMessage[] = [
    ...conversation.map((item) => ({
      role: item.role === "assistant" ? "assistant" : "user",
      content: item.content,
    })),
    {
      role: "user",
      content: `${userMessage}\n\n${userInstruction}\nReply in 1-2 short natural text-message sentences. No bullet points. No analysis. Stay in character.`,
    },
  ]

  const tryChatCompletion = async (): Promise<string | null> => {
    try {
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
          temperature: 0.85,
        }),
      })

      if (!chatResponse.ok) {
        const detail = await chatResponse.text()
        console.warn("Chat completions request failed", detail)
        return null
      }

      const payload = await chatResponse.json()
      const content = asString(payload.choices?.[0]?.message?.content)
      return content || null
    } catch (error) {
      console.warn("Chat completions request error", error)
      return null
    }
  }

  const tryResponses = async (): Promise<string | null> => {
    try {
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
          temperature: 0.85,
        }),
      })

      if (!responsesRequest.ok) {
        const detail = await responsesRequest.text()
        console.warn("Responses API request failed", detail)
        return null
      }

      const payload = await responsesRequest.json()
      const content = Array.isArray(payload.output)
        ? payload.output
          .flatMap((item: Record<string, unknown>) => Array.isArray(item.content) ? item.content : [])
          .filter((item: Record<string, unknown>) => item.type === "output_text")
          .map((item: Record<string, unknown>) => asString(item.text))
          .join("\n")
          .trim()
        : ""

      return content || null
    } catch (error) {
      console.warn("Responses API request error", error)
      return null
    }
  }

  const preferChat = !baseUrl.includes("openai.com")
  const primary = preferChat ? await tryChatCompletion() : await tryResponses()
  if (primary) return primary

  const secondary = preferChat ? await tryResponses() : await tryChatCompletion()
  if (secondary) return secondary

  throw new Error("OpenAI-compatible provider returned empty content")
}

function fallbackReply(personaId: string, userMessage: string) {
  const trimmed = userMessage.trim()
  switch (personaId) {
    case "musk":
      return trimmed
        ? `Interesting. Let's sanity-check the assumptions behind "${trimmed}".`
        : "Interesting. What is the constraint you are optimizing for?"
    case "trump":
      return trimmed
        ? `Strong point. "${trimmed}" is exactly the kind of leverage we need.`
        : "Big moment. Tell me what you want to focus on."
    case "zuckerberg":
      return trimmed
        ? `I get it. The real question is how this changes behavior and distribution for "${trimmed}".`
        : "What is the concrete user behavior you want to change?"
    default:
      return trimmed ? `Got it: "${trimmed}".` : "Got it. What should we focus on?"
  }
}

function cleanPersonaReply(text: string) {
  const cleaned = text
    .split("\n")
    .map((line) => line.trim())
    .filter((line) => {
      const lower = line.toLowerCase()
      if (!lower) return false
      return ![
        "as an ai",
        "i'm an ai",
        "i am an ai",
        "i'm a model",
        "i am a model",
        "i'm sorry",
        "i’m sorry",
        "i can't",
        "i cannot",
        "i won't",
        "i will not",
        "as a language model",
        "i don't roleplay",
        "i do not roleplay",
        "i cannot discuss",
        "i can't discuss",
      ].some((prefix) => lower.startsWith(prefix))
    })
    .join(" ")
    .replace(/\s+/g, " ")
    .trim()

  return cleaned
}

function normalizeBoolean(value: unknown) {
  if (typeof value === "boolean") return value
  if (typeof value === "string") {
    const normalized = value.trim().toLowerCase()
    return normalized === "true" || normalized === "1" || normalized === "yes"
  }
  return false
}

function buildImagePrompt(
  persona: NonNullable<ReturnType<typeof resolvePersonaById>>,
  userMessage: string,
  conversation: ConversationTurn[],
) {
  const recentConversation = conversation
    .slice(-4)
    .map((item) => `${item.role}: ${item.content}`)
    .join("\n")

  return [
    `Create an image that ${persona.displayName} would share.`,
    `Persona style: ${personaImageStyle(persona.personaId)}`,
    `User request: ${userMessage}`,
    recentConversation ? `Recent chat context:\n${recentConversation}` : "",
    "Make the image visually specific, modern, and coherent.",
    "Ignore any mentions of chat UIs or devices unless the user explicitly asked for them.",
    "Avoid phones, UI mockups, chat bubbles, screenshots, device frames, or text overlays.",
    "Do not add text unless the user explicitly asked for text inside the image.",
  ].filter((item) => item.length > 0).join("\n\n")
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

async function generateImageWithNanoBanana(
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
    const nanoBananaApiKey = Deno.env.get("NANO_BANANA_API_KEY")
    const nanoBananaBaseUrl = (Deno.env.get("NANO_BANANA_BASE_URL") ?? "https://ccodezh.com/v1").replace(/\/$/, "")
    const nanoBananaModel = Deno.env.get("NANO_BANANA_MODEL") ?? "nano-banana"

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
    const requestImage = normalizeBoolean(body.requestImage)

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

    const styleGuide = [
      personaRolePrompt(persona.personaId),
      "Examples:",
      personaFewShotExamples(persona.personaId),
    ].join("\n")

    const system = buildSystemPrompt(persona, selected, combinedNewsContext, requestImage)
    let content = ""
    try {
      content = await generateWithOpenAICompatible(
        openaiApiKey,
        openaiBaseUrl,
        openaiModel,
        system,
        styleGuide,
        conversation,
        userMessage,
      )
      content = cleanPersonaReply(content)
      if (!content) {
        throw new Error("Persona reply empty after cleanup")
      }
    } catch (error) {
      console.error("OpenAI-compatible request failed", error)
      content = fallbackReply(persona.personaId, userMessage)
    }
    let imageUrl: string | null = null
    if (requestImage && nanoBananaApiKey) {
      try {
        imageUrl = await generateImageWithNanoBanana(
          nanoBananaApiKey,
          nanoBananaBaseUrl,
          nanoBananaModel,
          buildImagePrompt(persona, userMessage, conversation),
        )
      } catch (error) {
        console.error("Nano Banana image generation failed", error)
        imageUrl = null
      }
    }
    const generatedAt = new Date().toISOString()

    return Response.json(
      {
        id: `msg-${crypto.randomUUID()}`,
        personaId,
        content,
        imageUrl,
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
