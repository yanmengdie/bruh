import { createClient } from "jsr:@supabase/supabase-js@2"
import { corsHeaders } from "../_shared/cors.ts"

type IncomingNote = {
  noteId?: string
  title?: string
  rawText?: string
  noteUrl?: string
  exploreUrl?: string
  likeCount?: string | number
  isPinned?: boolean
  publishedAt?: string
  rawPayload?: Record<string, unknown>
}

function asString(value: unknown): string {
  return typeof value === "string" ? value.trim() : ""
}

function slugify(value: string): string {
  const normalized = value
    .trim()
    .toLowerCase()
    .replace(/[^a-z0-9\u4e00-\u9fa5]+/g, "-")
    .replace(/^-+|-+$/g, "")

  return normalized || crypto.randomUUID()
}

function parseCount(value: unknown): number {
  if (typeof value === "number" && Number.isFinite(value)) return value
  if (typeof value !== "string") return 0

  const normalized = value.trim().replace(/,/g, "")
  if (!normalized) return 0

  if (normalized.endsWith("万")) {
    const parsed = Number.parseFloat(normalized.slice(0, -1))
    return Number.isFinite(parsed) ? Math.round(parsed * 10000) : 0
  }

  const parsed = Number.parseFloat(normalized)
  return Number.isFinite(parsed) ? parsed : 0
}

function stripQuery(url: string): string {
  const trimmed = url.trim()
  if (!trimmed) return ""

  try {
    const parsed = new URL(trimmed)
    parsed.search = ""
    parsed.hash = ""
    return parsed.toString()
  } catch {
    return trimmed.split("?")[0] ?? trimmed
  }
}

function preferredSourceUrl(note: IncomingNote, profileUrl: string | null): string | null {
  const exploreUrl = stripQuery(asString(note.exploreUrl))
  if (exploreUrl) return exploreUrl

  const noteUrl = stripQuery(asString(note.noteUrl))
  if (noteUrl) return noteUrl

  return profileUrl ? stripQuery(profileUrl) : null
}

function sanitizeNote(note: IncomingNote): Record<string, unknown> {
  return {
    noteId: asString(note.noteId),
    title: asString(note.title),
    rawText: asString(note.rawText),
    noteUrl: stripQuery(asString(note.noteUrl)),
    exploreUrl: stripQuery(asString(note.exploreUrl)),
    likeCount: note.likeCount ?? null,
    isPinned: note.isPinned === true,
    publishedAt: asString(note.publishedAt),
    rawPayload: note.rawPayload ?? null,
  }
}

function computeImportanceScore(note: IncomingNote): number {
  const likes = parseCount(note.likeCount)
  const pinnedBoost = note.isPinned ? 0.08 : 0
  const rawScore = 0.52 + Math.min(likes / 5000, 0.39) + pinnedBoost
  return Math.round(Math.min(rawScore, 0.99) * 100) / 100
}

function extractContent(note: IncomingNote): string {
  const title = asString(note.title)
  if (title.length > 0) return title

  const rawText = asString(note.rawText)
    .replace(/\s+/g, " ")
    .trim()

  if (rawText.length === 0) {
    return "小红书新动态"
  }

  return rawText.length > 160 ? rawText.slice(0, 160).trim() : rawText
}

function resolvePublishedAt(note: IncomingNote, index: number): string {
  const candidate = asString(note.publishedAt)
  if (candidate) {
    const date = new Date(candidate)
    if (!Number.isNaN(date.getTime())) {
      return date.toISOString()
    }
  }

  return new Date(Date.now() - index * 1000).toISOString()
}

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders })
  }

  try {
    const url = Deno.env.get("PROJECT_URL")
    const serviceRoleKey = Deno.env.get("SERVICE_ROLE_KEY")

    if (!url || !serviceRoleKey) {
      return Response.json(
        { error: "Missing Supabase environment variables" },
        { status: 500, headers: corsHeaders },
      )
    }

    const body = request.method === "POST" ? await request.json().catch(() => ({})) : {}
    const displayName = asString(body.displayName)
    const personaId = asString(body.personaId) || displayName
    const userId = asString(body.userId)
    const sourceHandle = asString(body.sourceHandle) || `xhs:${userId || slugify(displayName || personaId)}`
    const profileUrl = asString(body.profileUrl) || null
    const notes = Array.isArray(body.notes) ? body.notes as IncomingNote[] : []

    if (!displayName || !personaId) {
      return Response.json(
        { error: "Missing displayName or personaId" },
        { status: 400, headers: corsHeaders },
      )
    }

    if (notes.length === 0) {
      return Response.json(
        { error: "No notes provided" },
        { status: 400, headers: corsHeaders },
      )
    }

    const supabase = createClient(url, serviceRoleKey)

    const { error: personaError } = await supabase
      .from("personas")
      .upsert({
        id: personaId,
        x_username: sourceHandle,
        display_name: displayName,
        is_active: true,
      }, { onConflict: "id" })

    if (personaError) {
      throw new Error(personaError.message)
    }

    const rows = notes.map((note, index) => {
      const noteId = asString(note.noteId) || crypto.randomUUID()
      return {
        id: `xhs-${slugify(personaId)}-${noteId}`,
        persona_id: personaId,
        source_type: "xiaohongshu",
        content: extractContent(note),
        source_url: preferredSourceUrl(note, profileUrl),
        topic: "小红书",
        importance_score: computeImportanceScore(note),
        published_at: resolvePublishedAt(note, index),
        raw_author_username: displayName,
        raw_payload: {
          platform: "xiaohongshu",
          displayName,
          personaId,
          userId,
          profileUrl: profileUrl ? stripQuery(profileUrl) : null,
          note: sanitizeNote(note),
        },
      }
    })

    const { data, error: upsertError } = await supabase
      .from("source_posts")
      .upsert(rows, { onConflict: "id" })
      .select("id")

    if (upsertError) {
      throw new Error(upsertError.message)
    }

    return Response.json(
      {
        ok: true,
        personaId,
        displayName,
        inserted: data?.length ?? rows.length,
        notes: rows.length,
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
