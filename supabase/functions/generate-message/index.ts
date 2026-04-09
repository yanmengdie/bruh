import { createClient } from "jsr:@supabase/supabase-js@2"
import { corsHeaders } from "../_shared/cors.ts"
import { topNewsSummaryBlock } from "../_shared/news.ts"
import { resolvePersonaById } from "../_shared/personas.ts"
import {
  personaDistilledChatPrompt,
  personaFewShotExamples,
  personaImageStyle,
  personaRolePrompt,
} from "../_shared/persona_skills.ts"

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

type VoiceMood = "fired_up" | "angry" | "smug" | "urgent"

type VoicePlan = {
  shouldGenerate: boolean
  speakerId: string
  voiceLabel: string
  emoText: string
  emoVector: number[]
  emoAlpha: number
}

type TTSResponse = {
  task_id?: string
  status?: string
  message?: string
  output_path?: string | null
  audio_url?: string | null
  duration?: number | null
}

const MAX_GENERATION_RETRIES = 3

function asString(value: unknown): string {
  return typeof value === "string" ? value.trim() : ""
}

function countRegexMatches(text: string, pattern: RegExp) {
  return text.match(pattern)?.length ?? 0
}

function clamp(value: number, min: number, max: number) {
  return Math.min(max, Math.max(min, value))
}

async function delay(ms: number) {
  await new Promise((resolve) => setTimeout(resolve, ms))
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
  const distilledSkillBlock = personaDistilledChatPrompt(persona.personaId)

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
    `If the user asks who you are, how to address you, or asks for a self-introduction, answer naturally in first person and you may explicitly say your name is ${persona.displayName}.`,
    "Give a sharp opinion first. If useful, end with one short follow-up question.",
    "Stay in character and keep it natural.",
    distilledSkillBlock,
    "Examples of the desired style:",
    personaFewShotExamples(persona.personaId),
    "Recent context:",
    contextBlock,
    newsBlock,
  ].filter((item) => item.length > 0)

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

function buildProviderMessages(
  styleGuide: string,
  conversation: ConversationTurn[],
  userMessage: string,
): OpenAIMessage[] {
  const userInstruction = [
    "STYLE GUIDE (mandatory):",
    styleGuide,
    "Use the persona's voice and signature cadence.",
    "Do not mention being an AI or assistant.",
  ].join("\n")

  return [
    ...conversation.map((item) => ({
      role: item.role === "assistant" ? "assistant" : "user",
      content: item.content,
    })),
    {
      role: "user",
      content: `${userMessage}\n\n${userInstruction}\nReply in 1-2 short natural text-message sentences. No bullet points. No analysis. Stay in character.`,
    },
  ]
}

async function generateWithAnthropic(
  apiKey: string,
  baseUrl: string,
  model: string,
  system: string,
  styleGuide: string,
  conversation: ConversationTurn[],
  userMessage: string,
) {
  const response = await fetch(`${baseUrl}/v1/messages`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "x-api-key": apiKey,
      "anthropic-version": "2023-06-01",
    },
    body: JSON.stringify({
      model,
      max_tokens: 120,
      temperature: 0.85,
      system,
      messages: buildProviderMessages(styleGuide, conversation, userMessage).map((message) => ({
        role: message.role,
        content: message.content,
      })),
    }),
  })

  if (!response.ok) {
    throw new Error(`Anthropic request failed: ${await response.text()}`)
  }

  const payload = await response.json()
  const content = Array.isArray(payload.content)
    ? payload.content
      .filter((block: Record<string, unknown>) => block.type === "text")
      .map((block: Record<string, unknown>) => asString(block.text))
      .join("\n")
      .trim()
    : ""

  if (!content) {
    throw new Error("Anthropic returned empty content")
  }

  return content
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

function resolveVoiceSpeakerId(
  persona: NonNullable<ReturnType<typeof resolvePersonaById>>,
) {
  const overrideKey = `VOICE_SPEAKER_${persona.personaId.toUpperCase()}`
  return asString(Deno.env.get(overrideKey)) || persona.defaultVoiceSpeakerId
}

function classifyVoiceMood(content: string): VoiceMood {
  const lower = content.toLowerCase()
  const angerSignals = [
    "fake news",
    "lie",
    "liar",
    "disaster",
    "ridiculous",
    "离谱",
    "假的",
    "胡扯",
    "扯淡",
    "weak",
    "loser",
    "losers",
    "wrong",
    "stupid",
    "terrible",
  ]
  const smugSignals = [
    "believe me",
    "everyone knows",
    "obviously",
    "of course",
    "keep up",
    "i told you",
  ]
  const urgentSignals = [
    "now",
    "right now",
    "asap",
    "immediately",
    "today",
    "马上",
    "现在",
    "立刻",
    "move fast",
    "ship it",
    "accelerate",
  ]

  if (angerSignals.some((signal) => lower.includes(signal))) return "angry"
  if (smugSignals.some((signal) => lower.includes(signal))) return "smug"
  if (urgentSignals.some((signal) => lower.includes(signal))) return "urgent"
  return "fired_up"
}

function voiceMoodVector(mood: VoiceMood) {
  switch (mood) {
    case "angry":
      return [0.04, 0.58, 0.03, 0.06, 0.12, 0.02, 0.05, 0.1]
    case "smug":
      return [0.24, 0.03, 0.02, 0.01, 0.01, 0.01, 0.12, 0.56]
    case "urgent":
      return [0.08, 0.18, 0.03, 0.15, 0.02, 0.02, 0.2, 0.32]
    case "fired_up":
    default:
      return [0.34, 0.14, 0.02, 0.02, 0.02, 0.01, 0.3, 0.15]
  }
}

function voiceMoodText(
  persona: NonNullable<ReturnType<typeof resolvePersonaById>>,
  mood: VoiceMood,
) {
  switch (mood) {
    case "angry":
      return `${persona.displayName}, sharp and emotionally charged, slightly angry, clipped delivery, high conviction`
    case "smug":
      return `${persona.displayName}, smug and self-assured, playful swagger, relaxed control, confident emphasis`
    case "urgent":
      return `${persona.displayName}, urgent and activated, speaking faster than normal, focused pressure, emotionally elevated`
    case "fired_up":
    default:
      return `${persona.displayName}, energized and animated, speaking with momentum, confident, fired up, emotionally elevated`
  }
}

function shouldReplyWithVoice(
  personaId: string,
  content: string,
  requestImage: boolean,
) {
  if (requestImage || !content) return false

  const words = content.split(/\s+/).filter((word) => word.length > 0)
  if (words.length < 5 || words.length > 36) return false

  const lower = content.toLowerCase()
  const exclamationCount = countRegexMatches(content, /!/g)
  const uppercaseWordCount = countRegexMatches(content, /\b[A-Z]{3,}\b/g)
  const emojiCount = countRegexMatches(content, /[\p{Emoji_Presentation}\p{Extended_Pictographic}]/gu)
  const intenseSignalCount = [
    "huge",
    "massive",
    "crazy",
    "wild",
    "insane",
    "ridiculous",
    "离谱",
    "假的",
    "马上",
    "立刻",
    "fake news",
    "lie",
    "wrong",
    "winning",
    "believe me",
    "brutal",
    "disaster",
    "everyone knows",
    "move fast",
    "accelerate",
    "ship it",
    "absolutely",
  ].reduce((score, signal) => score + (lower.includes(signal) ? 1 : 0), 0)

  let score = 0
  score += clamp(exclamationCount, 0, 2)
  score += clamp(uppercaseWordCount, 0, 2)
  score += clamp(emojiCount, 0, 1)
  score += clamp(intenseSignalCount, 0, 3)

  if (personaId === "trump") score += 1
  if (/[?？]$/.test(content) && exclamationCount === 0 && uppercaseWordCount === 0) score -= 1

  return score >= 2
}

function buildVoicePlan(
  persona: NonNullable<ReturnType<typeof resolvePersonaById>>,
  content: string,
  requestImage: boolean,
): VoicePlan {
  if (!shouldReplyWithVoice(persona.personaId, content, requestImage)) {
    return {
      shouldGenerate: false,
      speakerId: "",
      voiceLabel: "",
      emoText: "",
      emoVector: [],
      emoAlpha: 0,
    }
  }

  const mood = classifyVoiceMood(content)
  return {
    shouldGenerate: true,
    speakerId: resolveVoiceSpeakerId(persona),
    voiceLabel: persona.defaultVoiceLabel,
    emoText: voiceMoodText(persona, mood),
    emoVector: voiceMoodVector(mood),
    emoAlpha: 0.92,
  }
}

function buildAbsoluteVoiceUrl(baseUrl: string, relativeOrAbsoluteUrl: string, taskId: string) {
  const sanitizedBaseUrl = baseUrl.replace(/\/$/, "")
  if (/^https?:\/\//i.test(relativeOrAbsoluteUrl)) return relativeOrAbsoluteUrl
  const normalizedPath = relativeOrAbsoluteUrl
    ? relativeOrAbsoluteUrl.replace(/^\//, "")
    : `audio/${taskId}`
  return new URL(normalizedPath, `${sanitizedBaseUrl}/`).toString()
}

async function synthesizeVoiceReply(
  voiceApiBaseUrl: string,
  voiceApiKey: string | null,
  plan: VoicePlan,
  content: string,
) {
  const response = await fetch(`${voiceApiBaseUrl}/tts/sync`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      ...(voiceApiKey ? { Authorization: `Bearer ${voiceApiKey}` } : {}),
    },
    body: JSON.stringify({
      text: content,
      speaker_id: plan.speakerId,
      use_emo_text: true,
      emo_text: plan.emoText,
      emo_vector: plan.emoVector,
      emo_alpha: plan.emoAlpha,
      max_text_tokens_per_segment: 120,
      top_p: 0.78,
      top_k: 30,
      temperature: 0.72,
      repetition_penalty: 6,
    }),
    signal: AbortSignal.timeout(20_000),
  })

  if (!response.ok) {
    throw new Error(`TTS request failed: ${await response.text()}`)
  }

  const payload = await response.json() as TTSResponse
  const taskId = asString(payload.task_id)
  const audioUrl = buildAbsoluteVoiceUrl(voiceApiBaseUrl, asString(payload.audio_url), taskId)

  if (!taskId || !audioUrl) {
    throw new Error("TTS response missing audio URL")
  }

  return {
    audioUrl,
    duration: typeof payload.duration === "number" ? payload.duration : null,
    voiceLabel: plan.voiceLabel,
  }
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
    const anthropicApiKey = Deno.env.get("ANTHROPIC_API_KEY")
    const anthropicBaseUrl = (Deno.env.get("ANTHROPIC_BASE_URL") ?? "https://api.anthropic.com").replace(/\/$/, "")
    const anthropicModel = Deno.env.get("ANTHROPIC_MODEL") ?? "claude-sonnet-4-5-20250929"
    const nanoBananaApiKey = Deno.env.get("NANO_BANANA_API_KEY")
    const nanoBananaBaseUrl = (Deno.env.get("NANO_BANANA_BASE_URL") ?? "https://ccodezh.com/v1").replace(/\/$/, "")
    const nanoBananaModel = Deno.env.get("NANO_BANANA_MODEL") ?? "nano-banana"
    const voiceApiKey = asString(Deno.env.get("VOICE_API_KEY")) || null
    const voiceApiBaseUrl = (
      Deno.env.get("VOICE_API_BASE_URL") ??
      "https://uu36540-775678b2e148.bjb2.seetacloud.com:8443/api"
    ).replace(/\/$/, "")

    if (!url || !serviceRoleKey || !anthropicApiKey) {
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
    const debugProviders = normalizeBoolean(body.debugProviders)

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
    const providerErrors: string[] = []
    let lastError: Error | null = null

    for (let attempt = 1; attempt <= MAX_GENERATION_RETRIES && !content; attempt += 1) {
      try {
        const candidate = cleanPersonaReply(await generateWithAnthropic(
          anthropicApiKey,
          anthropicBaseUrl,
          anthropicModel,
          system,
          styleGuide,
          conversation,
          userMessage,
        ))
        if (candidate) {
          content = candidate
          break
        }

        lastError = new Error("Persona reply empty after cleanup")
        providerErrors.push(`[attempt ${attempt}] anthropic: Provider returned empty content after cleanup`)
      } catch (error) {
        lastError = error instanceof Error ? error : new Error(String(error))
        providerErrors.push(`[attempt ${attempt}] anthropic: ${lastError.message}`)
      }

      if (!content && attempt < MAX_GENERATION_RETRIES) {
        await delay(200 * attempt)
      }
    }

    if (!content) {
      console.error("Model provider request failed after retries", lastError)
      return Response.json(
        {
          error: "Message generation failed after retries",
          ...(debugProviders ? { debug: { providerErrors } } : {}),
        },
        { status: 502, headers: corsHeaders },
      )
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
    let audioUrl: string | null = null
    let audioDuration: number | null = null
    let voiceLabel: string | null = null
    let audioOnly = false

    const voicePlan = buildVoicePlan(persona, content, requestImage)
    if (voicePlan.shouldGenerate) {
      try {
        const voiceReply = await synthesizeVoiceReply(
          voiceApiBaseUrl,
          voiceApiKey,
          voicePlan,
          content,
        )
        audioUrl = voiceReply.audioUrl
        audioDuration = voiceReply.duration
        voiceLabel = voiceReply.voiceLabel
        audioOnly = true
      } catch (error) {
        console.error("Voice synthesis failed", error)
      }
    }
    const generatedAt = new Date().toISOString()

    return Response.json(
      {
        id: `msg-${crypto.randomUUID()}`,
        personaId,
        content,
        imageUrl,
        audioUrl,
        audioDuration,
        voiceLabel,
        audioOnly,
        sourcePostIds: [...selected.map((row) => row.id), ...relevantNews.map((row) => row.id)],
        generatedAt,
        ...(debugProviders ? { debug: { providerErrors } } : {}),
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
