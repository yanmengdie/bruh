import { createClient } from "jsr:@supabase/supabase-js@2"
import { anthropicModelCandidates, isTerminalAnthropicError } from "../_shared/anthropic.ts"
import { corsHeaders } from "../_shared/cors.ts"
import { personaMap, resolvePersonaById } from "../_shared/personas.ts"
import { personaSocialPrompt } from "../_shared/persona_skills.ts"

type ExistingComment = {
  id: string
  authorId: string
  authorDisplayName: string
  content: string
  isViewer: boolean
  inReplyToCommentId: string | null
}

type StoredLikeRow = {
  id: string
  post_id: string
  author_id: string
  author_type: string
  author_display_name: string
  reason_code: string
  created_at: string
}

type StoredCommentRow = {
  id: string
  post_id: string
  author_id: string
  author_type: string
  author_display_name: string
  content: string
  reason_code: string
  in_reply_to_comment_id: string | null
  generation_mode: string
  created_at: string
}

type ContactProfile = {
  id: string
  username: string
  displayName: string
  stance: string
  domains: string[]
  triggerKeywords: string[]
  relationshipHint: string
}

type RankedContact = ContactProfile & {
  score: number
  reasonCodes: string[]
}

type PersonaProfile = {
  personaId: string
  displayName: string
  stance: string
  domains: string[]
  triggerKeywords: string[]
}

type ToolPayload = {
  likes?: Array<{
    authorId?: unknown
    reasonCode?: unknown
  }>
  comments?: Array<{
    authorId?: unknown
    content?: unknown
    reasonCode?: unknown
    inReplyToCommentId?: unknown
  }>
}

type SanitizedInteractionResult = {
  postId: string
  likes: Array<{
    id: string
    postId: string
    authorId: string
    authorDisplayName: string
    reasonCode: string
    createdAt: string
  }>
  comments: Array<{
    id: string
    postId: string
    authorId: string
    authorDisplayName: string
    content: string
    reasonCode: string
    inReplyToCommentId: string | null
    isViewer: boolean
    createdAt: string
  }>
  generatedAt: string
  metadata: {
    usedAuthorFallback: boolean
    generatedCommentCount: number
    generatedLikeCount: number
  }
}

const MAX_GENERATION_RETRIES = 3

function asString(value: unknown): string {
  return typeof value === "string" ? value.trim() : ""
}

function logGenerationEvent(event: string, details: Record<string, unknown>) {
  console.log(JSON.stringify({
    scope: "generate-post-interactions",
    event,
    ...details,
    loggedAt: new Date().toISOString(),
  }))
}

async function delay(ms: number) {
  await new Promise((resolve) => setTimeout(resolve, ms))
}

function keywordOverlapScore(text: string, keywords: string[]): number {
  const lower = text.toLowerCase()
  return keywords.reduce((score, keyword) => score + (lower.includes(keyword.toLowerCase()) ? 1 : 0), 0)
}

function relationshipHint(authorId: string, contactId: string): string {
  const hints: Record<string, Record<string, string>> = {
    musk: {
      zuckerberg: "Fellow tech builder and platform rival who reacts to AI and product strategy.",
      trump: "High-profile political ally who jumps into policy, tariffs, and culture-war topics.",
    },
    trump: {
      musk: "Political ally who reacts when business, AI, or national power is involved.",
      zuckerberg: "Platform founder whose products and moderation choices intersect with politics.",
    },
    zuckerberg: {
      musk: "Peer founder and competitor who reacts to AI, product launches, and internet culture.",
      trump: "Political figure whose media presence affects social products and public discourse.",
    },
  }

  return hints[authorId]?.[contactId] ?? "Knows the author and comments only when the topic clearly connects."
}

function resolvePersonaProfile(personaId: string): PersonaProfile {
  const resolved = resolvePersonaById(personaId)
  if (resolved) {
    return {
      personaId: resolved.personaId,
      displayName: resolved.displayName,
      stance: resolved.stance,
      domains: resolved.domains,
      triggerKeywords: resolved.triggerKeywords,
    }
  }

  return {
    personaId,
    displayName: personaId,
    stance: "grounded, concise, authentic, sounds like the real post author in a social app thread",
    domains: [],
    triggerKeywords: [],
  }
}

function acquaintanceIdsFor(authorId: string): string[] {
  return Object.keys(
    ({
      musk: {
        zuckerberg: true,
        trump: true,
      },
      trump: {
        musk: true,
        zuckerberg: true,
      },
      zuckerberg: {
        musk: true,
        trump: true,
      },
    } as Record<string, Record<string, boolean>>)[authorId] ?? {},
  )
}

function allContactsFor(authorId: string): ContactProfile[] {
  const knownIds = new Set(acquaintanceIdsFor(authorId))

  return Object.entries(personaMap)
    .map(([username, persona]) => ({
      id: persona.personaId,
      username,
      displayName: persona.displayName,
      stance: persona.stance,
      domains: persona.domains,
      triggerKeywords: persona.triggerKeywords,
      relationshipHint: relationshipHint(authorId, persona.personaId),
    }))
    .filter((contact) => contact.id !== authorId && knownIds.has(contact.id))
}

function extractMentionedPersonaIds(texts: string[]): Set<string> {
  const joined = texts.join("\n").toLowerCase()
  const mentions = new Set<string>()

  for (const [username, persona] of Object.entries(personaMap)) {
    const tokens = [
      username,
      persona.personaId,
      persona.displayName.toLowerCase(),
      `@${username}`,
      `@${persona.personaId}`,
    ]

    if (tokens.some((token) => token.length > 0 && joined.includes(token))) {
      mentions.add(persona.personaId)
    }
  }

  return mentions
}

function rankContacts(
  authorId: string,
  postContent: string,
  topic: string,
  existingComments: ExistingComment[],
  viewerComment: string,
): RankedContact[] {
  const mentionedIds = extractMentionedPersonaIds([postContent, viewerComment, topic])
  const threadParticipantIds = new Set(
    existingComments
      .map((comment) => comment.authorId)
      .filter((commentAuthorId) => commentAuthorId !== "viewer"),
  )
  const corpus = `${postContent}\n${topic}\n${viewerComment}`.trim()

  return allContactsFor(authorId)
    .map((contact) => {
      const reasonCodes: string[] = []
      let score = 1

      const overlap = keywordOverlapScore(corpus, contact.triggerKeywords)
      if (overlap > 0) {
        score += overlap * 3
        reasonCodes.push("topic_match")
      }

      if (mentionedIds.has(contact.id)) {
        score += 5
        reasonCodes.push("mention_hit")
      }

      if (threadParticipantIds.has(contact.id)) {
        score += 2
        reasonCodes.push("thread_participant")
      }

      if (contact.domains.some((domain) => topic.toLowerCase().includes(domain.toLowerCase()))) {
        score += 2
        reasonCodes.push("domain_fit")
      }

      reasonCodes.push("close_tie")

      return {
        ...contact,
        score,
        reasonCodes: [...new Set(reasonCodes)],
      }
    })
    .sort((left, right) => right.score - left.score || left.displayName.localeCompare(right.displayName))
}

function pickSeedCommenters(ranked: RankedContact[]): RankedContact[] {
  const strongMatches = ranked.filter((contact) => contact.score >= 3)
  return strongMatches.slice(0, 2)
}

function pickReplyParticipants(authorId: string, ranked: RankedContact[], viewerComment: string): RankedContact[] {
  const mentionedIds = extractMentionedPersonaIds([viewerComment])
  return ranked
    .filter((contact) => contact.id !== authorId && mentionedIds.has(contact.id))
    .slice(0, 1)
}

function displayNameFor(authorId: string): string {
  if (authorId === "viewer") return "你"
  return resolvePersonaProfile(authorId).displayName
}

function cleanGeneratedText(text: string): string {
  return text
    .split("\n")
    .filter((line) => {
      const lower = line.trim().toLowerCase()
      if (lower.length === 0) return false
      return ![
        "i'm cursor",
        "i am cursor",
        "i'm claude",
        "i am claude",
        "i'm gpt",
        "i am gpt",
        "i'm an ai",
        "i am an ai",
        "i'm a language model",
        "i am a language model",
      ].some((pattern) => lower.includes(pattern))
    })
    .join(" ")
    .replace(/\s+/g, " ")
    .replace(/\bmade by [^.?!]+[.?!]?/gi, "")
    .trim()
}

function isLowSignalViewerComment(viewerComment: string): boolean {
  const normalized = viewerComment.trim().toLowerCase()
  if (normalized.length <= 4) {
    return true
  }

  return [
    /^h+i+$/i,
    /^hello$/i,
    /^hey$/i,
    /^yo$/i,
    /^ok(ay)?$/i,
    /^cool$/i,
    /^nice$/i,
    /^wow$/i,
    /^lol$/i,
    /^哈+$/i,
    /^哈哈+$/i,
    /^嗯+$/i,
    /^哦+$/i,
    /^在吗$/i,
  ].some((pattern) => pattern.test(normalized))
}

function isLikelyEnglishText(text: string): boolean {
  const trimmed = text.trim()
  if (!trimmed) return false
  if (/[\u4e00-\u9fff]/.test(trimmed)) return false
  return /[a-z]/i.test(trimmed)
}

function modernReplyFallback(targetId: string, viewerComment: string): string {
  const lowSignal = isLowSignalViewerComment(viewerComment)
  const english = isLikelyEnglishText(viewerComment)

  switch (targetId) {
    case "musk":
      if (english) {
        return lowSignal ? "Just say what you want to say." : "I saw it. Say what you actually want to ask."
      }
      return lowSignal ? "直接说重点。" : "我看到了，直接说你想追问哪一点。"
    case "trump":
      if (english) {
        return lowSignal ? "Say it clearly." : "I saw it. Say what you actually think."
      }
      return lowSignal ? "直接说重点。" : "我看到了，直接说你的看法。"
    case "zuckerberg":
      if (english) {
        return lowSignal ? "Be a little more specific." : "I saw it. Be a little more specific."
      }
      return lowSignal ? "说具体一点，我更容易接住。" : "我看到了，讲具体一点会更有讨论价值。"
    case "sam_altman":
      if (english) {
        return lowSignal ? "Give me the concrete version." : "I saw it. Give me the concrete version."
      }
      return lowSignal ? "先说具体一点。" : "我看到了，你把最关键的那一层说具体一点。"
    case "zhang_peng":
      if (english) {
        return lowSignal ? "Give me the variable that matters." : "I saw it. Tell me which variable you care about."
      }
      return lowSignal ? "先讲变量。" : "我看到了，你先说你最在意的是哪个变量。"
    case "lei_jun":
      if (english) {
        return lowSignal ? "Say the real product point." : "I saw it. Tell me the real product point."
      }
      return lowSignal ? "直接说产品点。" : "我看到了，直接说你最关心的产品点。"
    case "liu_jingkang":
      if (english) {
        return lowSignal ? "What's the actual pain point?" : "I saw it. What's the actual pain point here?"
      }
      return lowSignal ? "痛点是什么？" : "我看到了，你直接说这里真正的痛点是什么。"
    case "luo_yonghao":
      if (english) {
        return lowSignal ? "Say it like a human." : "I saw it. Say it like a human."
      }
      return lowSignal ? "说人话。" : "我看到了，你直接说人话，别绕。"
    case "justin_sun":
      if (english) {
        return lowSignal ? "What's the trade?" : "I saw it. Tell me the trade you are seeing."
      }
      return lowSignal ? "你想表达什么交易判断？" : "我看到了，直接说你的交易判断。"
    case "kim_kardashian":
      if (english) {
        return lowSignal ? "Be specific." : "I saw it. Be specific about the signal."
      }
      return lowSignal ? "具体一点。" : "我看到了，你具体说这对文化还是品牌意味着什么。"
    case "papi":
      if (english) {
        return lowSignal ? "Give me an actual scene." : "I saw it. Give me an actual scene, not just a label."
      }
      return lowSignal ? "给我个具体场景。" : "我看到了，你先给我一个具体场景，不然太空了。"
    default:
      if (english) {
        return lowSignal ? "Say a little more." : "I saw it. Say what you want to discuss."
      }
      return lowSignal ? "说具体一点，我直接回你。" : "我看到了，直接说你想讨论哪一点。"
  }
}

function normalizeLegacyFallbackComment(authorId: string, content: string): string {
  const trimmed = content.trim()
  switch (authorId) {
    case "musk":
      if (trimmed === "政治也是现实的一部分。看现场就知道，大家会自己判断。") {
        return modernReplyFallback(authorId, "hi")
      }
      return trimmed
    case "trump":
      if (trimmed === "当然是真心的。现场的能量非常强，很多人都看到了。") {
        return modernReplyFallback(authorId, "hi")
      }
      return trimmed
    case "zuckerberg":
      if (trimmed === "这确实会被政治化，但现场反馈本身也是很真实的信号。") {
        return modernReplyFallback(authorId, "hi")
      }
      return trimmed
    default:
      return trimmed
  }
}

function templatedFallbackComment(targetId: string, authorDisplayName: string, viewerComment: string): string {
  if (viewerComment) {
    return modernReplyFallback(targetId, viewerComment)
  }

  switch (targetId) {
    case "musk":
      return `现场能量很强。${authorDisplayName}这条发得挺直接。`
    case "trump":
      return "这场面很强，真的很强。大家能感觉到那股势头。"
    case "zuckerberg":
      return "这种现场号召力挺少见的，传播效果会很强。"
    case "sam_altman":
      return "这条信息密度很高，后续的产品影响可能比表面更大。"
    case "zhang_peng":
      return "这条像是一个更大周期里的前置信号。"
    case "lei_jun":
      return "这条不只是热度，背后一定有产品和交付层的东西。"
    case "liu_jingkang":
      return "这条我会先看它到底击中了哪个真实场景。"
    case "luo_yonghao":
      return "这条确实值得聊，不然太浪费表达欲了。"
    case "justin_sun":
      return "这条会影响市场情绪，节奏不会慢。"
    case "kim_kardashian":
      return "这条很像会继续外溢的文化信号。"
    case "papi":
      return "这条下面一定会有人有代入感。"
    default:
      return "这条会让人想留言。"
  }
}

async function generateTextWithOpenAICompatible(
  apiKey: string,
  baseUrl: string,
  model: string,
  system: string,
  prompt: string,
) {
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
      max_output_tokens: 90,
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
      const cleaned = cleanGeneratedText(content)
      if (cleaned) return cleaned
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
      max_tokens: 90,
    }),
  })

  if (!chatResponse.ok) {
    throw new Error(`OpenAI-compatible request failed: ${await chatResponse.text()}`)
  }

  const payload = await chatResponse.json()
  const content = asString(payload.choices?.[0]?.message?.content)
  const cleaned = cleanGeneratedText(content)
  if (!cleaned) {
    throw new Error("OpenAI-compatible provider returned empty content")
  }

  return cleaned
}

async function generateInteractionsWithFallback(
  apiKey: string,
  baseUrl: string,
  model: string,
  authorId: string,
  postId: string,
  postContent: string,
  topic: string,
  existingComments: ExistingComment[],
  viewerComment: string,
  allowedLikes: RankedContact[],
  allowedCommenters: RankedContact[],
): Promise<SanitizedInteractionResult> {
  const author = resolvePersonaProfile(authorId)

  const generatedAt = new Date().toISOString()
  const likes = viewerComment
    ? []
    : allowedLikes.map((contact, index) => ({
      id: `like-${postId}-${contact.id}`,
      postId,
      authorId: contact.id,
      authorDisplayName: contact.displayName,
      reasonCode: contact.reasonCodes[0] ?? "close_tie",
      createdAt: new Date(Date.parse(generatedAt) + index * 1000).toISOString(),
    }))

  const comments: Array<{
    id: string
    postId: string
    authorId: string
    authorDisplayName: string
    content: string
    reasonCode: string
    inReplyToCommentId: string | null
    isViewer: boolean
    createdAt: string
  }> = []

  const targets = viewerComment
    ? [authorId, ...allowedCommenters.map((contact) => contact.id)]
    : allowedCommenters.map((contact) => contact.id)

  for (const [index, targetId] of targets.entries()) {
    const targetPersona = resolvePersonaProfile(targetId)

    const matchedContact = allowedCommenters.find((contact) => contact.id === targetId)
    const reason = matchedContact?.reasonCodes.join(", ") || (targetId === authorId ? "author_reply" : "topic_match")
    const system = [
      `You are ${targetPersona.displayName}.`,
      personaSocialPrompt(targetId),
      "You are writing a short comment under a social feed post, not sending a DM.",
      "Be concise, natural, specific, and in character.",
      "Maximum: 2 short sentences.",
      "No bullet points. No hashtags. No explanations about being an AI.",
      "Mirror the language of the post thread.",
      "Do not pivot to politics or any new topic unless the viewer comment or post clearly brings it up.",
      "If the viewer comment is only a greeting or very short, reply with a brief natural nudge in character.",
    ].join(" ")

    const prompt = viewerComment
      ? targetId === authorId
        ? [
          "Reply to a viewer comment under your own post.",
          `Your original post: ${postContent}`,
          `Viewer comment: ${viewerComment}`,
          `Thread so far: ${existingComments.map((comment) => `${comment.authorDisplayName}: ${comment.content}`).join(" | ") || "none"}`,
          "Keep the reply anchored to the viewer comment. Do not invent a new subject.",
          `React directly and stay in character. Why you care: ${reason}.`,
        ].join("\n")
        : [
          "You were mentioned or have a clear reason to join the thread.",
          `Original post by ${author.displayName}: ${postContent}`,
          `Viewer comment: ${viewerComment}`,
          `Add one short follow-up comment in your own voice. Why you care: ${reason}.`,
        ].join("\n")
      : [
        `You are reacting to ${author.displayName}'s social post.`,
        `Post: ${postContent}`,
        `Topic: ${topic || "none"}`,
        `Reason you care: ${reason}.`,
        "Write one short realistic comment in your own voice.",
      ].join("\n")

    let content = ""
    let lastError: string | null = null
    for (let attempt = 1; attempt <= MAX_GENERATION_RETRIES; attempt += 1) {
      try {
        content = await generateTextWithOpenAICompatible(apiKey, baseUrl, model, system, prompt)
        logGenerationEvent("openai_comment_success", {
          postId,
          authorId,
          targetId,
          mode: viewerComment ? "reply" : "seed",
          attempt,
          provider: "openai_compatible",
        })
        break
      } catch (error) {
        lastError = error instanceof Error ? error.message : String(error)
        logGenerationEvent("openai_comment_failure", {
          postId,
          authorId,
          targetId,
          mode: viewerComment ? "reply" : "seed",
          attempt,
          provider: "openai_compatible",
          error: lastError,
        })
        if (attempt < MAX_GENERATION_RETRIES) {
          await delay(200 * attempt)
        }
      }
    }

    if (!content) {
      content = templatedFallbackComment(targetId, author.displayName, viewerComment)
      logGenerationEvent("openai_comment_fallback", {
        postId,
        authorId,
        targetId,
        mode: viewerComment ? "reply" : "seed",
        provider: "openai_compatible",
        retries: MAX_GENERATION_RETRIES,
        error: lastError,
      })
    }

    comments.push({
      id: `comment-${postId}-${targetId}-${crypto.randomUUID()}`,
      postId,
      authorId: targetId,
      authorDisplayName: targetPersona.displayName,
      content,
      reasonCode: targetId === authorId ? "author_reply" : matchedContact?.reasonCodes[0] ?? "topic_match",
      inReplyToCommentId: viewerComment && index === 0 ? existingComments.at(-1)?.id ?? null : null,
      isViewer: false,
      createdAt: new Date(Date.parse(generatedAt) + index * 1000).toISOString(),
    })
  }

  return {
    postId,
    likes,
    comments,
    generatedAt,
    metadata: {
      usedAuthorFallback: false,
      generatedCommentCount: comments.length,
      generatedLikeCount: likes.length,
    },
  }
}

async function generateInteractionsWithClaude(
  apiKey: string,
  baseUrl: string,
  model: string,
  authorId: string,
  postContent: string,
  topic: string,
  existingComments: ExistingComment[],
  viewerComment: string,
  allowedLikes: RankedContact[],
  allowedCommenters: RankedContact[],
) {
  const author = resolvePersonaProfile(authorId)

  const mode = viewerComment ? "reply" : "seed"
  const allowedIds = new Set([
    ...allowedLikes.map((contact) => contact.id),
    ...allowedCommenters.map((contact) => contact.id),
    ...(viewerComment ? [authorId] : []),
  ])
  const contactLookups = [...allowedLikes, ...allowedCommenters]

  const allowedContacts = [authorId, ...Array.from(allowedIds).filter((id) => id !== authorId)]
    .map((id) => {
      if (id === authorId) {
        return {
          id,
          displayName: author.displayName,
          stance: author.stance,
          relationshipHint: "Post author",
        }
      }

      const contact = contactLookups.find((item) => item.id === id)
      return contact ? {
        id: contact.id,
        displayName: contact.displayName,
        stance: contact.stance,
        relationshipHint: contact.relationshipHint,
      } : null
    })
    .filter((item): item is NonNullable<typeof item> => item !== null)

  const response = await fetch(`${baseUrl}/v1/messages`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "x-api-key": apiKey,
      "anthropic-version": "2023-06-01",
    },
    body: JSON.stringify({
      model,
      max_tokens: 700,
      temperature: 0.2,
      system: [
        "You design believable social interactions for a WeChat Moments-style feed.",
        "Never invent people outside the allowed contacts.",
        "Every interaction must feel motivated by relationship, mentions, topic overlap, or thread context.",
        "Do not produce generic praise unless the persona would genuinely say it.",
        "Mirror the primary language of the post thread.",
        "Keep comments concise and social: usually 1 sentence, max 2 short sentences.",
        "Stay faithful to each persona's speaking style and worldview.",
        "If mode is reply, the post author must reply directly to the viewer comment.",
        "If mode is reply, keep the reply anchored to the viewer comment and do not invent a new topic.",
        "If the viewer comment is just a greeting or very short, answer with a short nudge in character.",
        "If mode is seed, only non-author contacts can comment.",
        "Return the result only through the tool call.",
      ].join(" "),
      messages: [{
        role: "user",
        content: [
          {
            type: "text",
            text: [
              `Mode: ${mode}`,
              `Post author: ${author.displayName} (${authorId})`,
              `Author stance: ${author.stance}`,
              `Post topic: ${topic || "none"}`,
              `Post content:\n${postContent}`,
              viewerComment ? `Viewer comment:\n${viewerComment}` : "Viewer comment: none",
              existingComments.length > 0
                ? `Existing thread:\n${existingComments.map((comment) => `- ${comment.authorDisplayName} (${comment.authorId}): ${comment.content}`).join("\n")}`
                : "Existing thread: none",
              `Allowed contacts:\n${allowedContacts.map((contact) => `- ${contact.displayName} (${contact.id}): ${contact.stance}. ${contact.relationshipHint}`).join("\n")}`,
              `Allowed like authors: ${allowedLikes.map((contact) => contact.id).join(", ") || "none"}`,
              `Allowed comment authors: ${(viewerComment ? [authorId, ...allowedCommenters.map((contact) => contact.id)] : allowedCommenters.map((contact) => contact.id)).join(", ") || "none"}`,
              "Allowed reason codes: mention_hit, topic_match, domain_fit, close_tie, thread_participant, author_reply, competitive_take.",
            ].join("\n\n"),
          },
        ],
      }],
      tools: [{
        name: "submit_interactions",
        description: "Return final likes and comments for this post interaction.",
        input_schema: {
          type: "object",
          properties: {
            likes: {
              type: "array",
              items: {
                type: "object",
                properties: {
                  authorId: { type: "string" },
                  reasonCode: { type: "string" },
                },
                required: ["authorId", "reasonCode"],
              },
            },
            comments: {
              type: "array",
              items: {
                type: "object",
                properties: {
                  authorId: { type: "string" },
                  content: { type: "string" },
                  reasonCode: { type: "string" },
                  inReplyToCommentId: {
                    anyOf: [
                      { type: "string" },
                      { type: "null" },
                    ],
                  },
                },
                required: ["authorId", "content", "reasonCode"],
              },
            },
          },
          required: ["likes", "comments"],
        },
      }],
      tool_choice: {
        type: "tool",
        name: "submit_interactions",
      },
    }),
  })

  if (!response.ok) {
    throw new Error(`Anthropic request failed: ${await response.text()}`)
  }

  const payload = await response.json()
  const blocks = Array.isArray(payload.content) ? payload.content : []
  const toolBlock = blocks.find((block: Record<string, unknown>) => block.type === "tool_use" && block.name === "submit_interactions")
  if (!toolBlock || typeof toolBlock !== "object") {
    throw new Error("Anthropic did not return a tool payload")
  }

  return (toolBlock.input ?? {}) as ToolPayload
}

function sanitizeGeneratedPayload(
  payload: ToolPayload,
  postId: string,
  authorId: string,
  viewerComment: string,
  allowedLikes: RankedContact[],
  allowedCommenters: RankedContact[],
  existingComments: ExistingComment[],
): SanitizedInteractionResult {
  const mode = viewerComment ? "reply" : "seed"
  const allowedLikeIds = new Set(allowedLikes.map((contact) => contact.id))
  const allowedCommentIds = new Set(allowedCommenters.map((contact) => contact.id))
  if (mode === "reply") {
    allowedCommentIds.add(authorId)
  }

  const generatedAt = new Date().toISOString()
  const likes = (payload.likes ?? [])
    .map((item) => ({
      authorId: asString(item.authorId),
      reasonCode: asString(item.reasonCode) || "close_tie",
    }))
    .filter((item) => allowedLikeIds.has(item.authorId))
    .filter((item, index, array) => array.findIndex((candidate) => candidate.authorId === item.authorId) === index)
    .map((item, index) => ({
      id: `like-${postId}-${item.authorId}`,
      postId,
      authorId: item.authorId,
      authorDisplayName: displayNameFor(item.authorId),
      reasonCode: item.reasonCode,
      createdAt: new Date(Date.parse(generatedAt) + index * 1000).toISOString(),
    }))

  const comments = (payload.comments ?? [])
    .map((item) => ({
      authorId: asString(item.authorId),
      content: cleanGeneratedText(asString(item.content)),
      reasonCode: asString(item.reasonCode) || (viewerComment ? "author_reply" : "topic_match"),
      inReplyToCommentId: asString(item.inReplyToCommentId) || null,
    }))
    .filter((item) => item.content.length > 0 && allowedCommentIds.has(item.authorId))
    .filter((item) => mode === "reply" || item.authorId !== authorId)
    .slice(0, 2)
    .map((item, index) => ({
      id: `comment-${postId}-${item.authorId}-${crypto.randomUUID()}`,
      postId,
      authorId: item.authorId,
      authorDisplayName: displayNameFor(item.authorId),
      content: item.content,
      reasonCode: item.reasonCode,
      inReplyToCommentId: item.inReplyToCommentId ?? (viewerComment && index === 0 ? existingComments.at(-1)?.id ?? null : null),
      isViewer: false,
      createdAt: new Date(Date.parse(generatedAt) + index * 1000).toISOString(),
    }))

  if (mode === "reply") {
    const generatedAuthorReply = comments.find((item) => item.authorId === authorId) ?? null
    const authorReply = generatedAuthorReply ?? {
      id: `comment-${postId}-${authorId}-${crypto.randomUUID()}`,
      postId,
      authorId,
      authorDisplayName: displayNameFor(authorId),
      content: templatedFallbackComment(authorId, displayNameFor(authorId), viewerComment),
      reasonCode: "author_reply",
      inReplyToCommentId: existingComments.at(-1)?.id ?? null,
      isViewer: false,
      createdAt: generatedAt,
    }

    const followUp = comments.find((item) => item.authorId !== authorId) ?? null
    return {
      postId,
      likes: [],
      comments: followUp ? [authorReply, followUp] : [authorReply],
      generatedAt,
      metadata: {
        usedAuthorFallback: generatedAuthorReply === null,
        generatedCommentCount: comments.length,
        generatedLikeCount: likes.length,
      },
    }
  }

  return {
    postId,
    likes: mode === "seed" ? likes : [],
    comments,
    generatedAt,
    metadata: {
      usedAuthorFallback: false,
      generatedCommentCount: comments.length,
      generatedLikeCount: likes.length,
    },
  }
}

function shouldAcceptSanitizedResult(
  result: SanitizedInteractionResult,
  authorId: string,
  viewerComment: string,
  allowedCommenters: RankedContact[],
): boolean {
  if (viewerComment) {
    const hasAuthorReply = result.comments.some((item) => item.authorId === authorId)
    return hasAuthorReply && !result.metadata.usedAuthorFallback
  }

  if (allowedCommenters.length === 0) {
    return true
  }

  return result.comments.length > 0 || result.likes.length > 0
}

function mapStoredState(postId: string, likes: StoredLikeRow[], comments: StoredCommentRow[]) {
  return {
    postId,
    likes: likes.map((item) => ({
      id: item.id,
      postId: item.post_id,
      authorId: item.author_id,
      authorDisplayName: item.author_display_name,
      reasonCode: item.reason_code,
      createdAt: item.created_at,
    })),
    comments: comments.map((item) => ({
      id: item.id,
      postId: item.post_id,
      authorId: item.author_id,
      authorDisplayName: item.author_display_name,
      content: normalizeLegacyFallbackComment(item.author_id, item.content),
      reasonCode: item.reason_code,
      inReplyToCommentId: item.in_reply_to_comment_id,
      isViewer: item.author_type === "viewer",
      createdAt: item.created_at,
    })),
    generatedAt: new Date().toISOString(),
  }
}

function normalizeStoredComments(rows: StoredCommentRow[]): ExistingComment[] {
  return rows.map((row) => ({
    id: row.id,
    authorId: row.author_id,
    authorDisplayName: row.author_display_name,
    content: normalizeLegacyFallbackComment(row.author_id, row.content),
    isViewer: row.author_type === "viewer",
    inReplyToCommentId: row.in_reply_to_comment_id,
  }))
}

async function fetchStoredState(supabase: ReturnType<typeof createClient>, postId: string) {
  const { data: likes, error: likesError } = await supabase
    .from("feed_likes")
    .select("id, post_id, author_id, author_type, author_display_name, reason_code, created_at")
    .eq("post_id", postId)
    .order("created_at", { ascending: true })

  if (likesError && !likesError.message.includes("feed_likes")) {
    throw new Error(likesError.message)
  }

  const { data: comments, error: commentsError } = await supabase
    .from("feed_comments")
    .select("id, post_id, author_id, author_type, author_display_name, content, reason_code, in_reply_to_comment_id, generation_mode, created_at")
    .eq("post_id", postId)
    .order("created_at", { ascending: true })

  if (commentsError && !commentsError.message.includes("feed_comments")) {
    throw new Error(commentsError.message)
  }

  return {
    likes: (likes ?? []) as StoredLikeRow[],
    comments: (comments ?? []) as StoredCommentRow[],
  }
}

async function persistLikes(
  supabase: ReturnType<typeof createClient>,
  likes: Array<{
    id: string
    postId: string
    authorId: string
    authorDisplayName: string
    reasonCode: string
    createdAt: string
  }>,
) {
  if (likes.length === 0) return

  const rows = likes.map((item) => ({
    id: item.id,
    post_id: item.postId,
    author_id: item.authorId,
    author_type: item.authorId === "viewer" ? "viewer" : "persona",
    author_display_name: item.authorDisplayName,
    reason_code: item.reasonCode,
    created_at: item.createdAt,
  }))

  const { error } = await supabase
    .from("feed_likes")
    .upsert(rows, { onConflict: "post_id,author_id" })

  if (error) {
    throw new Error(error.message)
  }
}

async function persistComments(
  supabase: ReturnType<typeof createClient>,
  comments: Array<{
    id: string
    postId: string
    authorId: string
    authorDisplayName: string
    content: string
    reasonCode: string
    inReplyToCommentId: string | null
    isViewer: boolean
    createdAt: string
    generationMode: "seed" | "reply" | "viewer"
  }>,
) {
  if (comments.length === 0) return

  const rows = comments.map((item) => ({
    id: item.id,
    post_id: item.postId,
    author_id: item.authorId,
    author_type: item.isViewer ? "viewer" : "persona",
    author_display_name: item.authorDisplayName,
    content: item.content,
    reason_code: item.reasonCode,
    in_reply_to_comment_id: item.inReplyToCommentId,
    generation_mode: item.generationMode,
    created_at: item.createdAt,
  }))

  const { error } = await supabase
    .from("feed_comments")
    .upsert(rows)

  if (error) {
    throw new Error(error.message)
  }
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
    const anthropicModels = anthropicModelCandidates(Deno.env.get("ANTHROPIC_MODEL"))
    const openaiApiKey = Deno.env.get("OPENAI_API_KEY")
    const openaiBaseUrl = (Deno.env.get("OPENAI_BASE_URL") ?? "https://api.codexzh.com/v1").replace(/\/$/, "")
    const openaiModel = Deno.env.get("OPENAI_MODEL") ?? "gpt-5.2"

    if (!projectUrl || !serviceRoleKey) {
      return Response.json({ error: "Missing Supabase environment variables" }, { status: 500, headers: corsHeaders })
    }

    const body = await request.json().catch(() => ({})) as Record<string, unknown>
    const postId = asString(body.postId)
    const personaId = asString(body.personaId)
    const postContent = asString(body.postContent)
    const topic = asString(body.topic)
    const viewerComment = asString(body.viewerComment)
    const viewerCommentId = asString(body.viewerCommentId) || `viewer-${crypto.randomUUID()}`
    const viewerLikeAction = asString(body.viewerLikeAction)

    if (!postId || !personaId || !postContent) {
      return Response.json(
        { error: "postId, personaId and postContent are required" },
        { status: 400, headers: corsHeaders },
      )
    }

    const supabase = createClient(projectUrl, serviceRoleKey)
    let stored = await fetchStoredState(supabase, postId)

    if (viewerLikeAction === "like" || viewerLikeAction === "unlike") {
      if (viewerLikeAction === "like") {
        await persistLikes(supabase, [{
          id: `like-${postId}-viewer`,
          postId,
          authorId: "viewer",
          authorDisplayName: "你",
          reasonCode: "viewer_like",
          createdAt: new Date().toISOString(),
        }])
      } else {
        const { error } = await supabase
          .from("feed_likes")
          .delete()
          .eq("post_id", postId)
          .eq("author_id", "viewer")

        if (error) {
          throw new Error(error.message)
        }
      }

      stored = await fetchStoredState(supabase, postId)
      return Response.json(mapStoredState(postId, stored.likes, stored.comments), { headers: corsHeaders })
    }

    if (!viewerComment) {
      if (stored.likes.length > 0 || stored.comments.length > 0) {
        return Response.json(mapStoredState(postId, stored.likes, stored.comments), { headers: corsHeaders })
      }

      const ranked = rankContacts(personaId, postContent, topic, [], "")
      const allowedCommenters = pickSeedCommenters(ranked)
      const allowedLikes = ranked
        .filter((contact) => allowedCommenters.some((commenter) => commenter.id === contact.id) || contact.score >= 2)
        .slice(0, 4)

      if (allowedCommenters.length === 0 && allowedLikes.length === 0) {
        return Response.json(mapStoredState(postId, stored.likes, stored.comments), { headers: corsHeaders })
      }

      let generated: SanitizedInteractionResult | null = null
      if (anthropicApiKey) {
        modelLoop:
        for (const anthropicModel of anthropicModels) {
          for (let attempt = 1; attempt <= MAX_GENERATION_RETRIES; attempt += 1) {
            try {
              const candidate = sanitizeGeneratedPayload(
                await generateInteractionsWithClaude(
                  anthropicApiKey,
                  anthropicBaseUrl,
                  anthropicModel,
                  personaId,
                  postContent,
                  topic,
                  [],
                  "",
                  allowedLikes,
                  allowedCommenters,
                ),
                postId,
                personaId,
                "",
                allowedLikes,
                allowedCommenters,
                [],
              )

              if (shouldAcceptSanitizedResult(candidate, personaId, "", allowedCommenters)) {
                generated = candidate
                logGenerationEvent("anthropic_seed_success", {
                  postId,
                  personaId,
                  attempt,
                  model: anthropicModel,
                  provider: "anthropic",
                  generatedCommentCount: candidate.metadata.generatedCommentCount,
                  generatedLikeCount: candidate.metadata.generatedLikeCount,
                })
                break modelLoop
              }

              logGenerationEvent("anthropic_seed_rejected", {
                postId,
                personaId,
                attempt,
                model: anthropicModel,
                provider: "anthropic",
                generatedCommentCount: candidate.metadata.generatedCommentCount,
                generatedLikeCount: candidate.metadata.generatedLikeCount,
                usedAuthorFallback: candidate.metadata.usedAuthorFallback,
              })
            } catch (error) {
              const errorMessage = error instanceof Error ? error.message : String(error)
              logGenerationEvent("anthropic_seed_failure", {
                postId,
                personaId,
                attempt,
                model: anthropicModel,
                provider: "anthropic",
                error: errorMessage,
              })

              if (isTerminalAnthropicError(errorMessage)) {
                break modelLoop
              }
            }

            if (attempt < MAX_GENERATION_RETRIES) {
              await delay(200 * attempt)
            }
          }
        }
      }

      if (!generated) {
        if (!openaiApiKey) {
          return Response.json({ error: "No valid model provider configured" }, { status: 500, headers: corsHeaders })
        }
        generated = await generateInteractionsWithFallback(
          openaiApiKey,
          openaiBaseUrl,
          openaiModel,
          personaId,
          postId,
          postContent,
          topic,
          [],
          "",
          allowedLikes,
          allowedCommenters,
        )
        logGenerationEvent("seed_provider_fallback", {
          postId,
          personaId,
          provider: "openai_compatible",
          reason: "anthropic_unavailable_or_rejected",
        })
      }

      await persistLikes(supabase, generated.likes)
      await persistComments(
        supabase,
        generated.comments.map((item) => ({ ...item, generationMode: "seed" as const })),
      )

      stored = await fetchStoredState(supabase, postId)
      return Response.json(mapStoredState(postId, stored.likes, stored.comments), { headers: corsHeaders })
    }

    const existingViewer = stored.comments.find((comment) => comment.id === viewerCommentId)
    if (!existingViewer) {
      await persistComments(supabase, [{
        id: viewerCommentId,
        postId,
        authorId: "viewer",
        authorDisplayName: "你",
        content: viewerComment,
        reasonCode: "viewer_input",
        inReplyToCommentId: null,
        isViewer: true,
        createdAt: new Date().toISOString(),
        generationMode: "viewer",
      }])
    }

    stored = await fetchStoredState(supabase, postId)
    const alreadyReplied = stored.comments.some((comment) =>
      comment.in_reply_to_comment_id === viewerCommentId &&
      comment.author_id === personaId,
    )
    if (alreadyReplied) {
      return Response.json(mapStoredState(postId, stored.likes, stored.comments), { headers: corsHeaders })
    }

    const existingComments = normalizeStoredComments(stored.comments)
    const ranked = rankContacts(personaId, postContent, topic, existingComments, viewerComment)
    const allowedCommenters = pickReplyParticipants(personaId, ranked, viewerComment)

    let replyResult: SanitizedInteractionResult | null = null
    if (anthropicApiKey) {
      modelLoop:
      for (const anthropicModel of anthropicModels) {
        for (let attempt = 1; attempt <= MAX_GENERATION_RETRIES; attempt += 1) {
          try {
            const candidate = sanitizeGeneratedPayload(
              await generateInteractionsWithClaude(
                anthropicApiKey,
                anthropicBaseUrl,
                anthropicModel,
                personaId,
                postContent,
                topic,
                existingComments,
                viewerComment,
                [],
                allowedCommenters,
              ),
              postId,
              personaId,
              viewerComment,
              [],
              allowedCommenters,
              existingComments,
            )

            if (shouldAcceptSanitizedResult(candidate, personaId, viewerComment, allowedCommenters)) {
              replyResult = candidate
              logGenerationEvent("anthropic_reply_success", {
                postId,
                personaId,
                attempt,
                model: anthropicModel,
                provider: "anthropic",
                generatedCommentCount: candidate.metadata.generatedCommentCount,
                usedAuthorFallback: candidate.metadata.usedAuthorFallback,
              })
              break modelLoop
            }

            logGenerationEvent("anthropic_reply_rejected", {
              postId,
              personaId,
              attempt,
              model: anthropicModel,
              provider: "anthropic",
              generatedCommentCount: candidate.metadata.generatedCommentCount,
              usedAuthorFallback: candidate.metadata.usedAuthorFallback,
            })
          } catch (error) {
            const errorMessage = error instanceof Error ? error.message : String(error)
            logGenerationEvent("anthropic_reply_failure", {
              postId,
              personaId,
              attempt,
              model: anthropicModel,
              provider: "anthropic",
              error: errorMessage,
            })

            if (isTerminalAnthropicError(errorMessage)) {
              break modelLoop
            }
          }

          if (attempt < MAX_GENERATION_RETRIES) {
            await delay(200 * attempt)
          }
        }
      }
    }

    if (!replyResult) {
      if (!openaiApiKey) {
        return Response.json({ error: "No valid model provider configured" }, { status: 500, headers: corsHeaders })
      }
      replyResult = await generateInteractionsWithFallback(
        openaiApiKey,
        openaiBaseUrl,
        openaiModel,
        personaId,
        postId,
        postContent,
        topic,
        existingComments,
        viewerComment,
        [],
        allowedCommenters,
      )
      logGenerationEvent("reply_provider_fallback", {
        postId,
        personaId,
        provider: "openai_compatible",
        reason: "anthropic_unavailable_or_rejected",
      })
    }

    await persistComments(
      supabase,
      replyResult.comments.map((item) => ({ ...item, generationMode: "reply" as const })),
    )

    stored = await fetchStoredState(supabase, postId)
    return Response.json(mapStoredState(postId, stored.likes, stored.comments), { headers: corsHeaders })
  } catch (error) {
    return Response.json(
      { error: error instanceof Error ? error.message : "Unknown error" },
      { status: 500, headers: corsHeaders },
    )
  }
})
