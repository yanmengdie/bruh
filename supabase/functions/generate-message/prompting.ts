import { topNewsSummaryBlock } from "../_shared/news.ts"
import type { PersonaDefinition } from "../_shared/personas.ts"
import {
  personaDistilledChatPrompt,
  personaFewShotExamples,
  personaRolePrompt,
} from "../_shared/persona_skills.ts"
import { asString, clamp, seededUnitInterval } from "./helpers.ts"
import type {
  ContextRow,
  ConversationTurn,
  NewsEventRow,
  OpenAIMessage,
  PersonaNewsScoreRow,
} from "./types.ts"

function replyLanguageLabel(persona: PersonaDefinition) {
  return persona.primaryLanguage === "en" ? "English" : "Chinese"
}

function replyLanguageInstruction(persona: PersonaDefinition) {
  if (persona.primaryLanguage === "en") {
    return "Reply only in natural English. Do not switch to Chinese, even if the user writes in Chinese."
  }
  return "只用自然中文回复。不要切换成英文，即使用户用英文提问。"
}

export function normalizeConversation(value: unknown): ConversationTurn[] {
  if (!Array.isArray(value)) return []

  return value
    .map((item) => ({
      role: asString((item as Record<string, unknown>).role),
      content: asString((item as Record<string, unknown>).content),
    }))
    .filter((item) => (item.role === "user" || item.role === "assistant") && item.content.length > 0)
    .slice(-6)
}

export function normalizeInterests(value: unknown): string[] {
  if (!Array.isArray(value)) return []
  return [...new Set(value.map((item) => asString(item)).filter((item) => item.length > 0))]
}

export function keywordOverlapScore(text: string, keywords: string[]): number {
  const lower = text.toLowerCase()
  return keywords.reduce((score, keyword) => score + (lower.includes(keyword.toLowerCase()) ? 1 : 0), 0)
}

export function selectContext(
  rows: ContextRow[],
  personaId: string,
  userMessage: string,
  triggerKeywords: string[],
): ContextRow[] {
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

export function selectRelevantNews(rows: PersonaNewsScoreRow[], userInterests: string[]): NewsEventRow[] {
  return rows
    .map((row) => Array.isArray(row.news_events) ? row.news_events[0] : row.news_events)
    .filter((row): row is NewsEventRow => row !== null)
    .filter((row) =>
      row.interest_tags.includes("global") || userInterests.some((interest) => row.interest_tags.includes(interest))
    )
    .slice(0, 3)
}

export function buildStructuredNewsContext(events: NewsEventRow[]): string {
  if (events.length === 0) return ""
  return [
    "Here are the news events most relevant right now:",
    ...events.map((event) => `- ${event.title} (${event.category}): ${event.summary}`),
  ].join("\n")
}

export function buildCombinedNewsContext(newsContext: string, relevantNews: NewsEventRow[]): string {
  return [
    newsContext,
    buildStructuredNewsContext(relevantNews),
    relevantNews.length > 0
      ? `Current top news snapshot:\n${
        topNewsSummaryBlock(relevantNews.map((event, index) => ({
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
        })))
      }`
      : "",
  ].filter((item) => item.length > 0).join("\n\n")
}

export function buildPersonaStyleGuide(persona: PersonaDefinition): string {
  return [
    personaRolePrompt(persona.personaId),
    "Examples:",
    personaFewShotExamples(persona.personaId),
  ].join("\n")
}

export function buildSystemPrompt(
  persona: PersonaDefinition,
  contextRows: ContextRow[],
  newsContext: string | undefined,
  requestImage: boolean,
): string {
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
    `Primary reply language: ${replyLanguageLabel(persona)}.`,
    replyLanguageInstruction(persona),
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

export function buildProviderMessages(
  persona: PersonaDefinition,
  styleGuide: string,
  conversation: ConversationTurn[],
  userMessage: string,
): OpenAIMessage[] {
  const userInstruction = [
    "STYLE GUIDE (mandatory):",
    styleGuide,
    "Use the persona's voice and signature cadence.",
    "Do not mention being an AI or assistant.",
    replyLanguageInstruction(persona),
  ].join("\n")

  return [
    ...conversation.map<OpenAIMessage>((item) => ({
      role: item.role === "assistant" ? "assistant" : "user",
      content: item.content,
    })),
    {
      role: "user",
      content: `${userMessage}\n\n${userInstruction}\nReply in 1-2 short natural text-message sentences. No bullet points. No analysis. Stay in character.`,
    },
  ]
}

function personaSourceShareBase(persona: PersonaDefinition) {
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
  if (
    [
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
    ].some((pattern) => lower.includes(pattern))
  ) {
    return true
  }

  return relevantNews.some((event) => keywordOverlapScore(lower, newsEventKeywords(event)) > 0)
}

export function resolveSharedSourceUrl(
  persona: PersonaDefinition,
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
