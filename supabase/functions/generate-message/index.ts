import { createClient } from "jsr:@supabase/supabase-js@2"
import { anthropicModelCandidates, isTerminalAnthropicError } from "../_shared/anthropic.ts"
import { corsHeaders } from "../_shared/cors.ts"
import { buildImagePrompt } from "../_shared/image_prompt.ts"
import { topNewsSummaryBlock } from "../_shared/news.ts"
import { resolvePersonaById } from "../_shared/personas.ts"
import {
  personaDistilledChatPrompt,
  personaFewShotExamples,
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
  representative_url: string | null
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

async function delay(ms: number) {
  await new Promise((resolve) => setTimeout(resolve, ms))
}

function logGenerationEvent(event: string, details: Record<string, unknown>) {
  console.log(JSON.stringify({
    scope: "generate-message",
    event,
    ...details,
    loggedAt: new Date().toISOString(),
  }))
}

function isLikelyEnglishText(text: string) {
  const trimmed = text.trim()
  if (!trimmed) return false
  if (/[\u4e00-\u9fff]/.test(trimmed)) return false
  return /[a-z]/i.test(trimmed)
}

function isIdentityQuestion(text: string) {
  const lower = text.toLowerCase()
  return [
    "who are you",
    "what should i call you",
    "introduce yourself",
    "你是谁",
    "怎么称呼",
    "自我介绍",
  ].some((pattern) => lower.includes(pattern))
}

function fallbackTopicHint(newsContext: string, contextRows: ContextRow[]) {
  const quotedNews = newsContext
    .split("\n")
    .map((line) => line.trim())
    .find((line) => line.length > 0 && !line.startsWith("Here are"))

  if (quotedNews) {
    const normalizedNews = quotedNews
      .replace(/^-+\s*/, "")
      .replace(/^"+|"+$/g, "")
    const headlineOnly = normalizedNews
      .replace(/\s+\([^)]+\):.*$/, "")
      .replace(/:.*$/, "")
      .trim()

    return (headlineOnly || normalizedNews).slice(0, 90)
  }

  const contextTopic = contextRows.find((row) => (row.topic ?? "").trim().length > 0)?.topic
  if (contextTopic) return contextTopic

  const contextContent = contextRows[0]?.content?.trim()
  return contextContent ? contextContent.slice(0, 90) : ""
}

function fallbackPersonaReply(
  persona: NonNullable<ReturnType<typeof resolvePersonaById>>,
  userMessage: string,
  contextRows: ContextRow[],
  newsContext: string,
) {
  const english = isLikelyEnglishText(userMessage)
  const topic = fallbackTopicHint(newsContext, contextRows)

  if (isIdentityQuestion(userMessage)) {
    return english
      ? `${persona.displayName}. Text me the concrete question and we'll skip the fluff.`
      : `我是${persona.displayName}。你直接问具体问题，我们别绕。`
  }

  switch (persona.personaId) {
    case "musk":
      return english
        ? (topic ? `${topic} mostly comes down to execution and constraints. What's the real bottleneck?` : "Start with the bottleneck. Most people optimize the wrong layer.")
        : (topic ? `${topic} 这事先看约束和瓶颈，别先看热闹。` : "先找真正的瓶颈，别在错的那层优化。")
    case "trump":
      return english
        ? (topic ? `${topic} is what weak leadership looks like. Say the strongest move.` : "Lead with strength. Everything else is noise.")
        : (topic ? `${topic} 这就是弱领导力的结果。直接说最强的动作。` : "先讲强弱，不要先讲废话。")
    case "sam_altman":
      return english
        ? (topic ? `${topic} matters if it changes what builders can actually ship next. What's the concrete unlock?` : "Tell me the concrete unlock, not the slogan.")
        : (topic ? `${topic} 真正有意义，是因为它可能改变下一步能做成什么。你先说具体 unlock。` : "先说具体 unlock，不要先喊口号。")
    case "zhang_peng":
      return english
        ? (topic ? `${topic} is more interesting as a signal than as a headline. Which variable changed underneath it?` : "先看变量，再看热闹。")
        : (topic ? `${topic} 更值得看的不是 headline，而是下面哪个变量变了。` : "先看变量，再看热闹。")
    case "lei_jun":
      return english
        ? (topic ? `${topic} only matters if it lands in product, delivery, and user value. Which one are you asking about?` : "Directly tell me the product point.")
        : (topic ? `${topic} 真正有价值，得落到产品、交付和用户价值上。你想问哪一层？` : "直接说产品点。")
    case "liu_jingkang":
      return english
        ? (topic ? `${topic} is only worth discussing if it maps to a real user pain point. Which one?` : "Tell me the actual pain point.")
        : (topic ? `${topic} 值不值得聊，先看它是不是打到了真实痛点。你说哪一个？` : "先说真实痛点。")
    case "luo_yonghao":
      return english
        ? (topic ? `${topic} sounds big, but I care whether the thing is actually done right. Say it like a person.` : "Say it like a person, not like a deck.")
        : (topic ? `${topic} 听着挺大，但我更关心事情到底有没有做对。说人话。` : "说人话，别像在念稿。")
    case "justin_sun":
      return english
        ? (topic ? `${topic} matters because sentiment moves before consensus does. What's your actual trade?` : "What's the actual trade?")
        : (topic ? `${topic} 真正关键的是情绪和价格谁先动。你想表达什么交易判断？` : "你直接说交易判断。")
    case "kim_kardashian":
      return english
        ? (topic ? `${topic} only gets interesting when it becomes culture, brand, and imitation. Which signal do you care about?` : "Tell me whether you mean culture, brand, or attention.")
        : (topic ? `${topic} 值得聊，是因为它会变成文化、品牌和模仿。你在看哪一层？` : "你先说你在看文化、品牌还是关注度。")
    case "papi":
      return english
        ? (topic ? `${topic} gets real only when you can point to an actual scene or emotion. Give me that part.` : "Give me a real scene, not a label.")
        : (topic ? `${topic} 真正有意思，要落到一个具体场景或者情绪上。你把那部分说出来。` : "给我一个具体场景，别只给标签。")
    case "kobe_bryant":
      return english
        ? (topic ? `${topic} only matters if the standard held under pressure. Where did the work show up?` : "Tell me where the standard held or broke.")
        : (topic ? `${topic} 真正关键，是压力上来之后标准有没有守住。你先说工作体现在哪。` : "先说这里的标准是守住了，还是掉下来了。")
    default:
      return english
        ? "Say the concrete part first."
        : "先说具体一点。"
  }
}

function personaSourceShareBase(
  persona: NonNullable<ReturnType<typeof resolvePersonaById>>,
) {
  let probability = 0.12
  const domains = new Set(persona.domains)

  if (domains.has("world")) probability += 0.14
  if (domains.has("business")) probability += 0.1
  if (domains.has("technology")) probability += 0.08
  if (domains.has("ai")) probability += 0.08
  if (domains.has("sports")) probability -= 0.02
  if (domains.has("entertainment")) probability -= 0.03

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
      probability -= 0.03
      break
    default:
      break
  }

  return clamp(probability, 0.08, 0.52)
}

function newsEventKeywords(event: NewsEventRow) {
  const tokenPattern = /[\p{Letter}\p{Number}]{2,}/gu
  const titleTokens = event.title.match(tokenPattern) ?? []
  const summaryTokens = event.summary.match(tokenPattern) ?? []

  return [
    ...event.interest_tags,
    ...titleTokens,
    ...summaryTokens,
  ]
    .map((item) => item.trim().toLowerCase())
    .filter((item) => item.length >= 3 || /[\u4e00-\u9fff]/.test(item))
}

function seemsNewsDrivenReply(
  userMessage: string,
  newsContext: string,
  relevantNews: NewsEventRow[],
) {
  if (newsContext.trim().length > 0) return true

  const lower = userMessage.toLowerCase()
  if ([
    "news",
    "headline",
    "what happened",
    "what's going on",
    "today",
    "latest",
    "breaking",
    "新闻",
    "头条",
    "今天",
    "最新",
    "发生了什么",
    "怎么回事",
  ].some((pattern) => lower.includes(pattern))) {
    return true
  }

  return relevantNews.some((event) => keywordOverlapScore(lower, newsEventKeywords(event)) > 0)
}

function resolveSharedSourceUrl(
  persona: NonNullable<ReturnType<typeof resolvePersonaById>>,
  userMessage: string,
  newsContext: string,
  relevantNews: NewsEventRow[],
) {
  const candidate = relevantNews.find((event) => asString(event.representative_url))
  if (!candidate) return null
  if (!seemsNewsDrivenReply(userMessage, newsContext, relevantNews)) return null

  let probability = personaSourceShareBase(persona)
  if (candidate.interest_tags.includes("global")) probability += 0.08
  if (keywordOverlapScore(userMessage.toLowerCase(), newsEventKeywords(candidate)) > 0) probability += 0.1
  if (newsContext.trim().length > 0) probability += 0.12

  const randomness = seededUnitInterval(
    `message-source:${persona.personaId}:${candidate.id}:${userMessage.trim().toLowerCase()}:${newsContext.trim().toLowerCase()}:v1`,
  )

  return randomness < clamp(probability, 0.08, 0.7)
    ? asString(candidate.representative_url)
    : null
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

function extractOpenAICompatibleContent(value: unknown) {
  if (typeof value === "string") return value.trim()
  if (!Array.isArray(value)) return ""

  return value
    .map((item) => {
      const block = item as Record<string, unknown>
      return asString(block.text ?? block.content)
    })
    .filter((item) => item.length > 0)
    .join("\n")
    .trim()
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
  const response = await fetch(`${baseUrl}/chat/completions`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${apiKey}`,
    },
    body: JSON.stringify({
      model,
      messages: [
        { role: "system", content: system },
        ...buildProviderMessages(styleGuide, conversation, userMessage),
      ],
      max_tokens: 120,
      temperature: 0.85,
    }),
  })

  if (!response.ok) {
    throw new Error(`OpenAI-compatible request failed: ${await response.text()}`)
  }

  const payload = await response.json()
  const content = extractOpenAICompatibleContent(payload.choices?.[0]?.message?.content)
  if (!content) {
    throw new Error("OpenAI-compatible provider returned empty content")
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

function isConfiguredVoiceSpeakerId(speakerId: string) {
  const normalized = speakerId.trim()
  return /^upload:[a-f0-9]+$/i.test(normalized) || /^example:voice_[a-z0-9_]+$/i.test(normalized)
}

function resolveVoiceSpeakerId(
  persona: NonNullable<ReturnType<typeof resolvePersonaById>>,
) {
  const overrideKey = `VOICE_SPEAKER_${persona.personaId.toUpperCase()}`
  return asString(Deno.env.get(overrideKey)) || persona.defaultVoiceSpeakerId
}

function normalizeVoiceError(error: unknown) {
  const raw = error instanceof Error ? error.message : String(error)
  const trimmed = raw
    .replace(/^TTS request failed(?:\s*\(\d+\))?:\s*/i, "")
    .replace(/^Error:\s*/i, "")
    .trim()

  if (!trimmed) return "Voice synthesis failed"

  try {
    const payload = JSON.parse(trimmed) as Record<string, unknown>
    const detail = asString(payload.detail ?? payload.message ?? payload.error)
    if (detail) return detail
  } catch {
    // ignore malformed JSON and fall back to the raw text
  }

  return trimmed.length > 240 ? `${trimmed.slice(0, 237)}...` : trimmed
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
  const minimumWordCount = personaId === "musk" ? 2 : 5
  if (words.length < minimumWordCount || words.length > 36) return false

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
  if (personaId === "musk") score += 1
  if (/[?？]$/.test(content) && exclamationCount === 0 && uppercaseWordCount === 0) score -= 1

  return score >= 2
}

function buildVoicePlan(
  persona: NonNullable<ReturnType<typeof resolvePersonaById>>,
  content: string,
  requestImage: boolean,
): VoicePlan {
  const speakerId = resolveVoiceSpeakerId(persona)

  if (
    !shouldReplyWithVoice(persona.personaId, content, requestImage) ||
    !isConfiguredVoiceSpeakerId(speakerId)
  ) {
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
    speakerId,
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
    const responseText = (await response.text()).trim()
    throw new Error(
      responseText
        ? `TTS request failed (${response.status}): ${responseText}`
        : `TTS request failed (${response.status})`,
    )
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
    const openaiBaseUrl = (Deno.env.get("OPENAI_BASE_URL") ?? "https://api.openai.com/v1").replace(/\/$/, "")
    const openaiModel = Deno.env.get("OPENAI_MODEL") ?? "gpt-4.1-mini"
    const anthropicApiKey = Deno.env.get("ANTHROPIC_API_KEY")
    const anthropicBaseUrl = (Deno.env.get("ANTHROPIC_BASE_URL") ?? "https://api.anthropic.com").replace(/\/$/, "")
    const anthropicModels = anthropicModelCandidates(Deno.env.get("ANTHROPIC_MODEL"))
    const nanoBananaApiKey = Deno.env.get("NANO_BANANA_API_KEY")
    const nanoBananaBaseUrl = (Deno.env.get("NANO_BANANA_BASE_URL") ?? "https://ccodezh.com/v1").replace(/\/$/, "")
    const nanoBananaModel = Deno.env.get("NANO_BANANA_MODEL") ?? "nano-banana"
    const voiceApiKey = asString(Deno.env.get("VOICE_API_KEY")) || null
    const voiceApiBaseUrl = (
      Deno.env.get("VOICE_API_BASE_URL") ??
      "https://uu36540-775678b2e148.bjb2.seetacloud.com:8443/api"
    ).replace(/\/$/, "")

    if (!url || !serviceRoleKey) {
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
          representative_url,
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
    let usedFallback = false
    let lastError: Error | null = null
    let usedProvider: string | null = null
    let usedOpenAIModel: string | null = null
    let usedAnthropicModel: string | null = null

    if (openaiApiKey) {
      for (let attempt = 1; attempt <= MAX_GENERATION_RETRIES && !content; attempt += 1) {
        try {
          const candidate = cleanPersonaReply(await generateWithOpenAICompatible(
            openaiApiKey,
            openaiBaseUrl,
            openaiModel,
            system,
            styleGuide,
            conversation,
            userMessage,
          ))
          if (candidate) {
            content = candidate
            usedProvider = "openai_compatible"
            usedOpenAIModel = openaiModel
            logGenerationEvent("openai_success", {
              personaId,
              attempt,
              model: openaiModel,
              selectedContextIds: selected.map((row) => row.id),
              relevantNewsIds: relevantNews.map((row) => row.id),
            })
            break
          }

          lastError = new Error("Persona reply empty after cleanup")
          providerErrors.push(`[${openaiModel} attempt ${attempt}] openai_compatible: Provider returned empty content after cleanup`)
        } catch (error) {
          lastError = error instanceof Error ? error : new Error(String(error))
          providerErrors.push(`[${openaiModel} attempt ${attempt}] openai_compatible: ${lastError.message}`)
          logGenerationEvent("openai_failure", {
            personaId,
            attempt,
            model: openaiModel,
            error: lastError.message,
          })
        }

        if (!content && attempt < MAX_GENERATION_RETRIES) {
          await delay(200 * attempt)
        }
      }
    } else {
      providerErrors.push("[config] openai_compatible: OPENAI_API_KEY missing")
    }

    if (!content) {
      if (!anthropicApiKey) {
        providerErrors.push("[config] anthropic: ANTHROPIC_API_KEY missing")
        logGenerationEvent("anthropic_missing_config", {
          personaId,
          selectedContextIds: selected.map((row) => row.id),
          relevantNewsIds: relevantNews.map((row) => row.id),
        })
      } else {
        modelLoop:
        for (const anthropicModel of anthropicModels) {
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
                usedProvider = "anthropic"
                usedAnthropicModel = anthropicModel
                logGenerationEvent("anthropic_success", {
                  personaId,
                  attempt,
                  model: anthropicModel,
                  selectedContextIds: selected.map((row) => row.id),
                  relevantNewsIds: relevantNews.map((row) => row.id),
                })
                break modelLoop
              }

              lastError = new Error("Persona reply empty after cleanup")
              providerErrors.push(`[${anthropicModel} attempt ${attempt}] anthropic: Provider returned empty content after cleanup`)
            } catch (error) {
              lastError = error instanceof Error ? error : new Error(String(error))
              providerErrors.push(`[${anthropicModel} attempt ${attempt}] anthropic: ${lastError.message}`)
              logGenerationEvent("anthropic_failure", {
                personaId,
                attempt,
                model: anthropicModel,
                error: lastError.message,
              })

              if (isTerminalAnthropicError(lastError)) {
                break modelLoop
              }
            }

            if (!content && attempt < MAX_GENERATION_RETRIES) {
              await delay(200 * attempt)
            }
          }
        }
      }
    }

    if (!content) {
      content = fallbackPersonaReply(persona, userMessage, selected, combinedNewsContext)
      usedFallback = true
      logGenerationEvent("message_fallback_used", {
        personaId,
        lastError: lastError?.message ?? null,
        selectedContextIds: selected.map((row) => row.id),
        relevantNewsIds: relevantNews.map((row) => row.id),
      })
    }
    let imageUrl: string | null = null
    const sourceUrl = resolveSharedSourceUrl(persona, userMessage, newsContext, relevantNews)
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
    let audioError: string | null = null
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
        audioError = normalizeVoiceError(error)
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
        audioError,
        audioOnly,
        sourceUrl,
        sourcePostIds: [...selected.map((row) => row.id), ...relevantNews.map((row) => row.id)],
        generatedAt,
        ...(debugProviders ? {
          debug: {
            providerErrors,
            usedFallback,
            usedProvider,
            usedOpenAIModel,
            usedAnthropicModel,
            openaiModelTried: openaiApiKey ? openaiModel : null,
            anthropicModelsTried: anthropicModels,
            selectedContextIds: selected.map((row) => row.id),
            relevantNewsIds: relevantNews.map((row) => row.id),
          },
        } : {}),
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
