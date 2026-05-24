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
  platformAccounts: { platform: string; handle: string; profileUrl: string | null; isPrimary: boolean; isActive: boolean }[]
}

export type ConversationTurn = { role: string; content: string }

export type ContextRow = {
  id: string
  persona_id: string
  content: string
  topic: string | null
  importance_score: number
  published_at: string
}

export type NewsEventRow = {
  id: string
  title: string
  summary: string
  category: string
  interest_tags: string[]
  representative_url: string | null
  importance_score: number
  published_at: string
}

export type PersonaNewsScoreRow = {
  score: number
  news_events: NewsEventRow | NewsEventRow[] | null
}

export type VoicePlan = {
  shouldGenerate: boolean
  speakerId: string
  voiceLabel: string
}
