import {
  assertValidPersonaCatalogData,
  type PersonaPlatformAccountRecord,
} from "./persona_catalog_schema.ts"
import personaCatalogData from "../../../bruh/SharedPersonas.json" with { type: "json" }

export type PersonaPlatformAccount = PersonaPlatformAccountRecord

export type PersonaDefinition = {
  personaId: string
  displayName: string
  stance: string
  domains: string[]
  leadInterestIds: string[]
  triggerKeywords: string[]
  entityKeywords: string[]
  defaultVoiceSpeakerId: string
  defaultVoiceLabel: string
  aliases: string[]
  xUsernames: string[]
  primaryLanguage: string
  friendGreeting: string
  socialCircleIds: string[]
  relationshipHints: Record<string, string>
  platformAccounts: PersonaPlatformAccount[]
}

export function normalizeUsername(value: string) {
  return value.replace(/^@/, "").trim().toLowerCase()
}

function uniqueStrings(values: string[]) {
  return [...new Set(values.map((value) => value.trim()).filter((value) => value.length > 0))]
}

function normalizeStringRecord(value: unknown): Record<string, string> {
  if (!value || typeof value !== "object") return {}

  return Object.fromEntries(
    Object.entries(value as Record<string, unknown>)
      .map(([key, item]) => [key, typeof item === "string" ? item.trim() : ""] as const)
      .filter((entry) => entry[1].length > 0),
  )
}

assertValidPersonaCatalogData(personaCatalogData)

const personaRecords = personaCatalogData.map((record) => ({
  ...record,
  aliases: uniqueStrings(record.aliases ?? []),
  triggerKeywords: uniqueStrings(record.triggerKeywords ?? []),
  entityKeywords: uniqueStrings(record.entityKeywords ?? []),
  domains: uniqueStrings(record.domains ?? []),
  leadInterestIds: uniqueStrings(record.leadInterestIds ?? []),
  socialCircleIds: uniqueStrings(record.socialCircleIds ?? []),
  platformAccounts: Array.isArray(record.platformAccounts)
    ? record.platformAccounts.map((account) => ({
      platform: String(account.platform ?? "").trim().toLowerCase(),
      handle: normalizeUsername(String(account.handle ?? "")),
      profileUrl: typeof account.profileUrl === "string" && account.profileUrl.trim().length > 0 ? account.profileUrl.trim() : null,
      isPrimary: account.isPrimary === true,
      isActive: account.isActive !== false,
    })).filter((account) => account.platform.length > 0 && account.handle.length > 0)
    : [],
}))

const personaDefinitions: PersonaDefinition[] = personaRecords.map((record) => {
  const xUsernames = record.platformAccounts
    .filter((account) => account.platform === "x")
    .map((account) => normalizeUsername(account.handle))

  return {
    personaId: record.id,
    displayName: record.displayName,
    stance: record.stance,
    domains: record.domains,
    leadInterestIds: record.leadInterestIds,
    triggerKeywords: record.triggerKeywords,
    entityKeywords: record.entityKeywords,
    defaultVoiceSpeakerId: record.defaultVoiceSpeakerId,
    defaultVoiceLabel: record.defaultVoiceLabel,
    aliases: uniqueStrings([record.id, record.displayName, ...record.aliases]),
    xUsernames,
    primaryLanguage: record.primaryLanguage,
    friendGreeting: record.friendGreeting,
    socialCircleIds: record.socialCircleIds,
    relationshipHints: normalizeStringRecord(record.relationshipHints),
    platformAccounts: record.platformAccounts,
  }
})

export const personaMap: Record<string, PersonaDefinition> = Object.fromEntries(
  personaDefinitions.map((persona) => [persona.personaId, persona]),
)

const personaLookup = new Map<string, PersonaDefinition>()

for (const persona of personaDefinitions) {
  const lookupKeys = [
    persona.personaId,
    ...persona.aliases,
    ...persona.xUsernames,
  ]

  for (const key of lookupKeys) {
    personaLookup.set(normalizeUsername(key), persona)
  }
}

export const defaultUsernames = [...new Set(
  personaDefinitions.flatMap((persona) =>
    persona.platformAccounts
      .filter((account) => account.platform === "x" && account.isActive)
      .map((account) => normalizeUsername(account.handle))
  ),
)]

export function resolvePersona(value: string) {
  return personaLookup.get(normalizeUsername(value)) ?? null
}

export function resolvePersonaById(personaId: string) {
  return personaMap[personaId] ?? null
}

export function allPersonaIds() {
  return Object.values(personaMap).map((persona) => persona.personaId)
}
