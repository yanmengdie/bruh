import { asString } from "../_shared/news.ts"
import type {
  StarterImageMode,
  StarterSelectionStrategy,
  StarterSourceUrlMode,
} from "../_shared/feature_flags.ts"
import { normalizeSourceUrl } from "../_shared/media.ts"
import { resolvePersonaById } from "../_shared/personas.ts"
import type {
  CandidateStarter,
  PersonaScoreRow,
  SelectedStarter,
  StarterEventRow,
} from "./types.ts"

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

export function normalizeInterests(value: unknown): string[] {
  if (!Array.isArray(value)) return []
  return [...new Set(value.map((item) => asString(item)).filter((item) => item.length > 0))]
}

function normalizeStringArray(value: unknown): string[] {
  if (!Array.isArray(value)) return []
  return [...new Set(value.map((item) => asString(item)).filter((item) => item.length > 0))]
}

function personaVisualShareBase(
  persona: NonNullable<ReturnType<typeof resolvePersonaById>>,
) {
  let probability = 0.12
  const domains = new Set(persona.domains)

  if (domains.has("entertainment")) probability += 0.14
  if (domains.has("sports")) probability += 0.1
  if (domains.has("creator")) probability += 0.08
  if (domains.has("world")) probability += 0.06
  if (domains.has("business")) probability += 0.04

  switch (persona.personaId) {
    case "trump":
    case "kim_kardashian":
    case "cristiano_ronaldo":
    case "musk":
    case "justin_sun":
      probability += 0.08
      break
    case "sam_altman":
    case "zhang_peng":
    default:
      break
  }

  return clamp(probability, 0.08, 0.52)
}

function personaSourceShareBase(
  persona: NonNullable<ReturnType<typeof resolvePersonaById>>,
) {
  let probability = 0.14
  const domains = new Set(persona.domains)

  if (domains.has("world")) probability += 0.14
  if (domains.has("business")) probability += 0.08
  if (domains.has("technology")) probability += 0.08
  if (domains.has("ai")) probability += 0.08
  if (domains.has("entertainment")) probability -= 0.02
  if (domains.has("sports")) probability -= 0.02

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
    case "cristiano_ronaldo":
      probability -= 0.04
      break
    default:
      break
  }

  return clamp(probability, 0.08, 0.58)
}

function starterImageProbability(
  persona: NonNullable<ReturnType<typeof resolvePersonaById>>,
  item: SelectedStarter,
) {
  let probability = personaVisualShareBase(persona)

  if (item.selectionReasons.includes("persona_related")) probability += 0.12
  if (item.selectionReasons.includes("global_top")) probability += 0.06
  if (item.event.is_global_top) probability += 0.06
  if (item.event.representative_url) probability += 0.04

  switch (item.event.category) {
    case "sports":
    case "entertainment":
    case "world":
      probability += 0.08
      break
    case "technology":
    case "business":
    case "ai":
    case "crypto":
      probability += 0.04
      break
    default:
      break
  }

  return clamp(probability, 0.08, 0.68)
}

export function pickStarterImageEventIds(
  selected: SelectedStarter[],
  imageMode: StarterImageMode = "adaptive",
) {
  if (imageMode === "disabled") {
    return new Set<string>()
  }

  const ranked = selected
    .map((item) => {
      const persona = resolvePersonaById(item.personaId)
      if (!persona) return null

      const probability = starterImageProbability(persona, item)
      const randomness = seededUnitInterval(`starter-image:${item.personaId}:${item.event.id}:v1`)

      if (randomness >= probability) return null

      return {
        eventId: item.event.id,
        personaId: item.personaId,
        priority:
          probability - randomness +
          (item.selectionReasons.includes("persona_related") ? 0.08 : 0) +
          (item.event.is_global_top ? 0.04 : 0),
      }
    })
    .filter((candidate): candidate is { eventId: string; personaId: string; priority: number } => candidate !== null)
    .sort((left, right) => right.priority - left.priority || left.personaId.localeCompare(right.personaId))

  const eventIds = new Set<string>()
  const seenPersonaIds = new Set<string>()

  for (const candidate of ranked) {
    if (seenPersonaIds.has(candidate.personaId)) continue
    eventIds.add(candidate.eventId)
    seenPersonaIds.add(candidate.personaId)
    if (eventIds.size >= 1) break
  }

  return eventIds
}

export function resolveStarterSourceUrl(
  personaId: string,
  item: CandidateStarter,
  sourceUrlMode: StarterSourceUrlMode = "adaptive",
) {
  const persona = resolvePersonaById(personaId)
  if (!persona) return null

  const url = normalizeSourceUrl(asString(item.event.representative_url))
  if (!url) return null

  if (sourceUrlMode === "always") return url
  if (sourceUrlMode === "never") return null

  let probability = personaSourceShareBase(persona)
  if (item.selectionReasons.includes("global_top")) probability += 0.08
  if (item.selectionReasons.includes("persona_related")) probability += 0.06
  if (item.event.is_global_top) probability += 0.04

  switch (item.event.category) {
    case "world":
    case "business":
    case "technology":
    case "ai":
    case "crypto":
      probability += 0.08
      break
    case "sports":
    case "entertainment":
      probability -= 0.02
      break
    default:
      break
  }

  const randomness = seededUnitInterval(`starter-source:${persona.personaId}:${item.event.id}:v1`)
  return randomness < clamp(probability, 0.08, 0.76) ? url : null
}

function pickPersonaForEvent(scores: PersonaScoreRow[], selectionReasons: string[]) {
  let ranked = scores

  if (selectionReasons.includes("persona_related")) {
    const entityHitRows = scores.filter((row) => normalizeStringArray(row.reason_codes).includes("entity_hit"))
    if (entityHitRows.length > 0) {
      ranked = entityHitRows
    }
  }

  return ranked
    .slice()
    .sort((left, right) => right.score - left.score || left.persona_id.localeCompare(right.persona_id))[0] ?? null
}

export function collectSelectedStarters(
  events: StarterEventRow[],
  scoresByEvent: Map<string, PersonaScoreRow[]>,
  userInterests: string[],
  options: {
    strategy?: StarterSelectionStrategy
    allowedPersonaIds?: Set<string>
  } = {},
) {
  const strategy = options.strategy ?? "balanced"
  const allowedPersonaIds = options.allowedPersonaIds ?? null
  const reasonsByEvent = new Map<string, Set<string>>()

  const globalEvents = events
    .filter((event) => event.is_global_top)
    .sort((left, right) => (left.global_rank ?? 999) - (right.global_rank ?? 999))
    .slice(0, 10)

  for (const event of globalEvents) {
    const reasons = reasonsByEvent.get(event.id) ?? new Set<string>()
    reasons.add("global_top")
    reasonsByEvent.set(event.id, reasons)
  }

  if (strategy === "balanced" && userInterests.length > 0) {
    const interestEvents = events
      .filter((event) => !event.is_global_top && userInterests.includes(event.category))
      .sort((left, right) =>
        right.importance_score - left.importance_score ||
        Date.parse(right.published_at) - Date.parse(left.published_at)
      )
      .slice(0, 10)

    for (const event of interestEvents) {
      const reasons = reasonsByEvent.get(event.id) ?? new Set<string>()
      reasons.add("interest_match")
      reasonsByEvent.set(event.id, reasons)
    }
  }

  if (strategy === "balanced") {
    const personaRelatedEvents = events.filter((event) =>
      (scoresByEvent.get(event.id) ?? []).some((row) => normalizeStringArray(row.reason_codes).includes("entity_hit"))
    )

    for (const event of personaRelatedEvents) {
      const reasons = reasonsByEvent.get(event.id) ?? new Set<string>()
      reasons.add("persona_related")
      reasonsByEvent.set(event.id, reasons)
    }
  }

  const selected: SelectedStarter[] = []

  for (const event of events) {
    const selectionReasons = [...(reasonsByEvent.get(event.id) ?? new Set<string>())]
    if (selectionReasons.length === 0) continue

    const scores = (scoresByEvent.get(event.id) ?? []).filter((row) =>
      !allowedPersonaIds || allowedPersonaIds.has(row.persona_id)
    )
    const pickedScore = pickPersonaForEvent(scores, selectionReasons)
    if (!pickedScore) continue

    selected.push({
      event,
      personaId: pickedScore.persona_id,
      score: pickedScore.score,
      selectionReasons,
    })
  }

  if (selected.length > 0) {
    return selected.sort((left, right) =>
      Date.parse(left.event.published_at) - Date.parse(right.event.published_at) ||
      (left.event.global_rank ?? 999) - (right.event.global_rank ?? 999) ||
      left.personaId.localeCompare(right.personaId)
    )
  }

  const fallbackEvent = events.find((event) => event.is_global_top) ?? events[0] ?? null
  if (!fallbackEvent) return []

  const fallbackScores = (scoresByEvent.get(fallbackEvent.id) ?? []).filter((row) =>
    !allowedPersonaIds || allowedPersonaIds.has(row.persona_id)
  )
  const fallbackScore = pickPersonaForEvent(fallbackScores, ["fallback_global_top"])
  if (!fallbackScore) return []

  return [{
    event: fallbackEvent,
    personaId: fallbackScore.persona_id,
    score: fallbackScore.score,
    selectionReasons: ["fallback_global_top"],
  }]
}
