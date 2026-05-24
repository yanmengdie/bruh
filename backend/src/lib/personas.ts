import { readFileSync } from "node:fs"
import { join, dirname } from "node:path"
import { fileURLToPath } from "node:url"
import type { PersonaDefinition } from "../types.js"

const __dirname = dirname(fileURLToPath(import.meta.url))
const dataDir = join(__dirname, "../../data")

const personaCatalog = JSON.parse(readFileSync(join(dataDir, "SharedPersonas.json"), "utf-8"))
const voiceSamples: Record<string, string> = JSON.parse(readFileSync(join(dataDir, "voice_samples.json"), "utf-8"))

type RawPersona = Record<string, any>

function uniqueStrings(values: string[]): string[] {
  return [...new Set(values.map(v => v.trim()).filter(v => v.length > 0))]
}

function normalizeUsername(value: string): string {
  return value.replace(/^@/, "").trim().toLowerCase()
}

const personaDefinitions: PersonaDefinition[] = (personaCatalog as RawPersona[]).map(record => {
  const platformAccounts = Array.isArray(record.platformAccounts)
    ? record.platformAccounts.map((a: any) => ({
        platform: String(a.platform ?? "").trim().toLowerCase(),
        handle: normalizeUsername(String(a.handle ?? "")),
        profileUrl: typeof a.profileUrl === "string" && a.profileUrl.trim().length > 0 ? a.profileUrl.trim() : null,
        isPrimary: a.isPrimary === true,
        isActive: a.isActive !== false,
      })).filter((a: any) => a.platform.length > 0 && a.handle.length > 0)
    : []

  const xUsernames = platformAccounts
    .filter((a: any) => a.platform === "x")
    .map((a: any) => normalizeUsername(a.handle))

  return {
    personaId: record.id,
    displayName: record.displayName,
    stance: record.stance,
    domains: uniqueStrings(record.domains ?? []),
    leadInterestIds: uniqueStrings(record.leadInterestIds ?? []),
    triggerKeywords: uniqueStrings(record.triggerKeywords ?? []),
    entityKeywords: uniqueStrings(record.entityKeywords ?? []),
    defaultVoiceSpeakerId: record.defaultVoiceSpeakerId,
    defaultVoiceLabel: record.defaultVoiceLabel,
    aliases: uniqueStrings([record.id, record.displayName, ...(record.aliases ?? [])]),
    xUsernames,
    primaryLanguage: record.primaryLanguage,
    friendGreeting: record.friendGreeting,
    socialCircleIds: uniqueStrings(record.socialCircleIds ?? []),
    relationshipHints: Object.fromEntries(
      Object.entries(record.relationshipHints ?? {})
        .filter(([_, v]) => typeof v === "string" && (v as string).trim().length > 0)
        .map(([k, v]) => [k, (v as string).trim()])
    ),
    platformAccounts,
  }
})

export const personaMap: Record<string, PersonaDefinition> = Object.fromEntries(
  personaDefinitions.map(p => [p.personaId, p])
)

const personaLookup = new Map<string, PersonaDefinition>()
for (const persona of personaDefinitions) {
  for (const key of [persona.personaId, ...persona.aliases, ...persona.xUsernames]) {
    personaLookup.set(normalizeUsername(key), persona)
  }
}

export function resolvePersona(value: string): PersonaDefinition | null {
  return personaLookup.get(normalizeUsername(value)) ?? null
}

export function resolvePersonaById(personaId: string): PersonaDefinition | null {
  return personaMap[personaId] ?? null
}

export function allPersonaIds(): string[] {
  return personaDefinitions.map(p => p.personaId)
}

export function resolveVoiceSampleDataUrl(personaId: string): string | null {
  const sample = voiceSamples[personaId]
  return sample && sample.startsWith("data:audio/") ? sample : null
}
