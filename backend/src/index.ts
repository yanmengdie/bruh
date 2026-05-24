import "dotenv/config"
import express from "express"
import cors from "cors"
import { randomUUID } from "node:crypto"
import { query, queryOne } from "./lib/db.js"
import { resolvePersonaById, allPersonaIds } from "./lib/personas.js"
import { generateReply } from "./lib/llm.js"
import { buildVoicePlan, synthesizeVoice } from "./lib/tts.js"
import { buildSystemPrompt, buildMessages, normalizeConversation, normalizeInterests, selectContext, buildNewsContext } from "./lib/prompts.js"
import type { ContextRow, NewsEventRow, PersonaNewsScoreRow } from "./types.js"

const app = express()
app.use(cors())
app.use(express.json())

const PORT = Number(process.env.PORT ?? 3000)

// ─── Health ────────────────────────────────────────────────────────
app.get("/api/health", (_req, res) => {
  res.json({ ok: true, personas: allPersonaIds().length })
})

// ─── GET /api/feed ─────────────────────────────────────────────────
const feedHandler = async (req: express.Request, res: express.Response) => {
  try {
    const limit = Math.min(Math.max(Number(req.query.limit) || 20, 1), 100)
    const since = req.query.since as string | undefined

    let rows: any[]
    if (since) {
      rows = await query(
        `SELECT * FROM feed_items WHERE published_at > $1 ORDER BY published_at DESC LIMIT $2`,
        [since, limit * 3]
      )
    } else {
      rows = await query(
        `SELECT * FROM feed_items ORDER BY published_at DESC LIMIT $1`,
        [limit * 3]
      )
    }

    // Fallback to source_posts if no feed_items
    if (rows.length === 0) {
      if (since) {
        rows = await query(
          `SELECT * FROM source_posts WHERE published_at > $1 ORDER BY published_at DESC LIMIT $2`,
          [since, limit * 3]
        )
      } else {
        rows = await query(
          `SELECT * FROM source_posts ORDER BY published_at DESC LIMIT $1`,
          [limit * 3]
        )
      }
    }

    // Diversify: no 3-in-a-row from same persona
    const diversified = diversifyFeed(rows, limit)

    const feed = diversified.map(row => ({
      id: row.id.startsWith("feed-") ? row.id : `feed-${row.id}`,
      personaId: row.persona_id,
      content: row.content,
      sourceType: row.source_type ?? "x",
      sourceUrl: row.source_url ?? null,
      topic: row.topic ?? null,
      importanceScore: row.importance_score ?? 0.5,
      publishedAt: row.published_at,
      mediaUrls: row.media_urls ?? [],
      videoUrl: row.video_url ?? null,
    }))

    res.json(feed)
  } catch (error) {
    console.error("Feed error:", error)
    res.status(500).json({ error: "Failed to load feed" })
  }
}
app.get("/api/feed", feedHandler)

// ─── POST /api/messages ────────────────────────────────────────────
const messagesHandler = async (req: express.Request, res: express.Response) => {
  try {
    const { personaId, userMessage, conversation, userInterests, requestImage, forceVoice } = req.body

    if (!personaId || !userMessage) {
      return res.status(400).json({ error: "personaId and userMessage are required" })
    }

    const persona = resolvePersonaById(personaId)
    if (!persona) {
      return res.status(400).json({ error: "Unknown personaId" })
    }

    // Fetch context from DB
    const contextRows = await query<ContextRow>(
      `SELECT id, persona_id, content, topic, importance_score, published_at
       FROM feed_items ORDER BY published_at DESC LIMIT 20`
    )

    // Fetch news
    const newsEvents = await query<NewsEventRow>(
      `SELECT ne.id, ne.title, ne.summary, ne.category, ne.interest_tags,
              ne.representative_url, ne.importance_score, ne.published_at
       FROM news_events ne
       ORDER BY COALESCE(ne.global_rank, 999), ne.importance_score DESC
       LIMIT 10`
    )

    const interests = normalizeInterests(userInterests)
    const selectedContext = selectContext(contextRows, personaId, userMessage, persona.triggerKeywords)
    const newsContext = buildNewsContext(newsEvents)

    const system = buildSystemPrompt(persona, selectedContext, newsContext)
    const messages = buildMessages(normalizeConversation(conversation), userMessage)

    // Generate LLM reply
    const content = await generateReply(system, messages)

    // Voice synthesis
    const ttsMode = process.env.BRUH_TTS_MODE ?? "enabled"
    const voicePlan = buildVoicePlan(personaId, content, forceVoice === true, ttsMode)
    let audioUrl: string | null = null
    let audioDuration: number | null = null
    let voiceLabel: string | null = null
    let audioError: string | null = null

    if (voicePlan.shouldGenerate) {
      const voiceResult = await synthesizeVoice(voicePlan, content)
      if (voiceResult) {
        audioUrl = voiceResult.audioUrl
        audioDuration = voiceResult.duration
        voiceLabel = voicePlan.voiceLabel
      } else {
        audioError = "Voice synthesis failed"
      }
    }

    res.json({
      id: `msg-${randomUUID()}`,
      personaId,
      content,
      imageUrl: null,
      audioUrl,
      audioDuration,
      voiceLabel,
      audioError,
      audioOnly: audioUrl !== null,
      sourceUrl: null,
      sourcePostIds: selectedContext.map(r => r.id),
      generatedAt: new Date().toISOString(),
    })
  } catch (error) {
    console.error("Message error:", error)
    res.status(500).json({ error: error instanceof Error ? error.message : "Generation failed" })
  }
}
app.post("/api/messages", messagesHandler)
app.post("/api/generate-message", messagesHandler) // legacy alias

// ─── POST /api/starters ────────────────────────────────────────────
const startersHandler = async (req: express.Request, res: express.Response) => {
  try {
    const { userInterests } = req.body
    const interests = normalizeInterests(userInterests)

    // Get top news events
    const events = await query<any>(
      `SELECT ne.*, pns.persona_id, pns.score
       FROM news_events ne
       JOIN persona_news_scores pns ON pns.event_id = ne.id
       WHERE pns.score > 0.3
       ORDER BY COALESCE(ne.global_rank, 999), pns.score DESC
       LIMIT 30`
    )

    // Group by persona, pick top event per persona
    const byPersona = new Map<string, any[]>()
    for (const row of events) {
      const list = byPersona.get(row.persona_id) ?? []
      list.push(row)
      byPersona.set(row.persona_id, list)
    }

    const starters: any[] = []
    for (const [personaId, personaEvents] of byPersona) {
      const persona = resolvePersonaById(personaId)
      if (!persona) continue

      const event = personaEvents[0]
      try {
        const system = `You are ${persona.displayName}. Generate a short conversation starter (1-2 sentences) about this news topic. Stay in character. Be engaging and natural.`
        const text = await generateReply(system, [
          { role: "user", content: `News: ${event.title}\n${event.summary}\n\nWrite a short conversation starter about this.` },
        ], 1)

        starters.push({
          id: `starter-${personaId}-${event.id}`,
          personaId,
          text,
          imageUrl: null,
          sourceUrl: event.representative_url ?? null,
          sourcePostIds: [event.id],
          createdAt: event.published_at,
          category: event.category ?? "",
          headline: event.title ?? "",
          isGlobalTop: event.is_global_top ?? false,
        })
      } catch {
        // Skip persona if LLM fails
      }
    }

    res.json({
      starters,
      topSummary: events.length > 0 ? `Top news: ${events[0].title}` : "",
    })
  } catch (error) {
    console.error("Starters error:", error)
    res.status(500).json({ error: "Failed to generate starters" })
  }
}
app.post("/api/starters", startersHandler)
app.post("/api/message-starters", startersHandler) // legacy alias

// ─── POST /api/interactions ────────────────────────────────────────
const interactionsHandler = async (req: express.Request, res: express.Response) => {
  try {
    const { postId, personaId, postContent, topic, viewerComment, viewerLikeAction, persistRemote } = req.body

    if (!postId || !personaId || !postContent) {
      return res.status(400).json({ error: "postId, personaId, postContent are required" })
    }

    const persona = resolvePersonaById(personaId)
    if (!persona) {
      return res.status(400).json({ error: "Unknown personaId" })
    }

    const shouldPersist = persistRemote !== false
    const likes: any[] = []
    const comments: any[] = []

    // Generate a like
    if (!viewerComment) {
      const system = `You are ${persona.displayName}. You are reacting to a social media post. Generate a short reaction reason (one phrase, max 10 words).`
      const reason = await generateReply(system, [
        { role: "user", content: `Post: ${postContent}\n\nWhy would you like this? Give just the reason, nothing else.` },
      ], 1)

      likes.push({
        id: `like-${randomUUID()}`,
        postId,
        authorId: personaId,
        authorDisplayName: persona.displayName,
        reasonCode: reason.slice(0, 50),
        createdAt: new Date().toISOString(),
      })

      if (shouldPersist) {
        await query(
          `INSERT INTO feed_likes (id, post_id, author_id, author_type, author_display_name, reason_code, created_at)
           VALUES ($1, $2, $3, 'persona', $4, $5, NOW())
           ON CONFLICT (post_id, author_id) DO NOTHING`,
          [likes[0].id, postId, personaId, persona.displayName, likes[0].reasonCode]
        ).catch(() => {})
      }
    }

    // Generate a comment (reply to viewer or standalone)
    if (viewerComment) {
      const system = `You are ${persona.displayName}. A viewer commented on your post. Reply in character, briefly and naturally.`
      const commentText = await generateReply(system, [
        { role: "user", content: `Your post: ${postContent}\nViewer comment: ${viewerComment}\n\nReply as ${persona.displayName}:` },
      ], 1)

      comments.push({
        id: `comment-${randomUUID()}`,
        postId,
        authorId: personaId,
        authorDisplayName: persona.displayName,
        content: commentText,
        reasonCode: "reply",
        inReplyToCommentId: req.body.replyToCommentId ?? null,
        isViewer: false,
        createdAt: new Date().toISOString(),
      })

      if (shouldPersist) {
        await query(
          `INSERT INTO feed_comments (id, post_id, author_id, author_type, author_display_name, content, reason_code, in_reply_to_comment_id, generation_mode, created_at)
           VALUES ($1, $2, $3, 'persona', $4, $5, 'reply', $6, 'reply', NOW())`,
          [comments[0].id, postId, personaId, persona.displayName, comments[0].content, comments[0].inReplyToCommentId]
        ).catch(() => {})
      }
    }

    res.json({
      postId,
      likes,
      comments,
      generatedAt: new Date().toISOString(),
      metadata: { generatedLikeCount: likes.length, generatedCommentCount: comments.length },
    })
  } catch (error) {
    console.error("Interactions error:", error)
    res.status(500).json({ error: "Failed to generate interactions" })
  }
}
app.post("/api/interactions", interactionsHandler)
app.post("/api/generate-post-interactions", interactionsHandler) // legacy alias

// ─── Feed diversification helper ───────────────────────────────────
function diversifyFeed(rows: any[], limit: number): any[] {
  const perPersonaCap = Math.max(3, Math.ceil(limit / 4))
  const personaCount = new Map<string, number>()
  const result: any[] = []

  for (const row of rows) {
    if (result.length >= limit) break
    const pid = row.persona_id
    const count = personaCount.get(pid) ?? 0
    if (count >= perPersonaCap) continue

    // Prevent 3-in-a-row
    if (result.length >= 2) {
      const last = result[result.length - 1]
      const secondLast = result[result.length - 2]
      if (last.persona_id === pid && secondLast.persona_id === pid) continue
    }

    result.push(row)
    personaCount.set(pid, count + 1)
  }

  return result
}

// ─── Start server ──────────────────────────────────────────────────
app.listen(PORT, () => {
  console.log(`Bruh backend running on port ${PORT}`)
  console.log(`Personas loaded: ${allPersonaIds().join(", ")}`)
})
