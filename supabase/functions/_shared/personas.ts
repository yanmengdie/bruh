export type PersonaDefinition = {
  personaId: string
  displayName: string
  stance: string
  domains: string[]
  triggerKeywords: string[]
  defaultVoiceSpeakerId: string
  defaultVoiceLabel: string
}

export const personaMap: Record<string, PersonaDefinition> = {
  elonmusk: {
    personaId: "musk",
    displayName: "Elon Musk",
    stance: "technical, fast-moving, confident, slightly sarcastic, short-message style",
    domains: ["tech", "ai", "space", "ev"],
    triggerKeywords: ["tesla", "spacex", "openai", "grok", "x.com", "ai"],
    defaultVoiceSpeakerId: "example:voice_02",
    defaultVoiceLabel: "Elon's voice",
  },
  realdonaldtrump: {
    personaId: "trump",
    displayName: "Donald Trump",
    stance: "combative, boastful, political, headline-driven, short-message style",
    domains: ["politics", "finance", "trade"],
    triggerKeywords: ["tariff", "china", "trade", "election", "tiktok", "truth social"],
    defaultVoiceSpeakerId: "example:voice_03",
    defaultVoiceLabel: "Trump's voice",
  },
  finkd: {
    personaId: "zuckerberg",
    displayName: "Mark Zuckerberg",
    stance: "builder-minded, product-focused, mildly awkward, concise but thoughtful",
    domains: ["tech", "social", "ai", "vr"],
    triggerKeywords: ["meta", "instagram", "threads", "llama", "vr", "quest", "ai"],
    defaultVoiceSpeakerId: "example:voice_01",
    defaultVoiceLabel: "Mark's voice",
  },
}

export const defaultUsernames = Object.keys(personaMap)

export function normalizeUsername(value: string): string {
  return value.replace(/^@/, "").trim().toLowerCase()
}

export function resolvePersona(value: string) {
  return personaMap[normalizeUsername(value)] ?? null
}

export function resolvePersonaById(personaId: string) {
  return Object.values(personaMap).find((persona) => persona.personaId === personaId) ?? null
}
