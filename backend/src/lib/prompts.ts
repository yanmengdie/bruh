import type { PersonaDefinition, ConversationTurn, ContextRow, NewsEventRow } from "../types.js"
import { personaRolePrompt, personaFewShotExamples } from "./persona_skills.js"

export function buildSystemPrompt(
  persona: PersonaDefinition,
  contextRows: ContextRow[],
  newsContext: string,
): string {
  const parts: string[] = []

  parts.push(`You are ${persona.displayName}. ${persona.stance}`)
  parts.push(personaRolePrompt(persona.personaId))

  parts.push(`Domains: ${persona.domains.join(", ")}`)
  parts.push(`Primary language: ${persona.primaryLanguage === "zh" ? "Chinese" : "English"}`)
  parts.push("Stay in character. Never break the fourth wall. Never mention being an AI.")

  if (contextRows.length > 0) {
    parts.push("\nRecent context:")
    for (const row of contextRows.slice(0, 3)) {
      parts.push(`- [${row.topic ?? "general"}] ${row.content.slice(0, 200)}`)
    }
  }

  if (newsContext) {
    parts.push(`\nNews context:\n${newsContext}`)
  }

  return parts.join("\n")
}

export function buildMessages(
  conversation: ConversationTurn[],
  userMessage: string,
): { role: "user" | "assistant"; content: string }[] {
  const messages: { role: "user" | "assistant"; content: string }[] = []

  for (const turn of conversation.slice(-6)) {
    if (turn.role === "user" || turn.role === "assistant") {
      messages.push({ role: turn.role, content: turn.content })
    }
  }

  messages.push({ role: "user", content: userMessage })
  return messages
}

export function normalizeConversation(raw: unknown): ConversationTurn[] {
  if (!Array.isArray(raw)) return []
  return raw
    .filter((t: any) => t && typeof t.role === "string" && typeof t.content === "string")
    .slice(-6)
    .map((t: any) => ({ role: t.role, content: t.content }))
}

export function normalizeInterests(raw: unknown): string[] {
  if (!Array.isArray(raw)) return []
  return [...new Set(raw.filter((i: any) => typeof i === "string" && i.trim().length > 0).map((i: string) => i.trim()))]
}

export function selectContext(rows: ContextRow[], personaId: string, userMessage: string, triggerKeywords: string[]): ContextRow[] {
  const lower = userMessage.toLowerCase()
  const scored = rows.map(row => {
    let score = row.importance_score
    if (row.persona_id === personaId) score += 0.3
    for (const kw of triggerKeywords) {
      if (lower.includes(kw.toLowerCase())) score += 0.2
    }
    return { row, score }
  })
  scored.sort((a, b) => b.score - a.score)
  return scored.slice(0, 3).map(s => s.row)
}

export function buildNewsContext(events: NewsEventRow[]): string {
  if (events.length === 0) return ""
  return events.map(e => `- ${e.title}: ${e.summary}`).join("\n")
}
