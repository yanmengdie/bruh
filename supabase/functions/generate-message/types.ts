export type ConversationTurn = {
  role: string
  content: string
}

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

export type OpenAIMessage = {
  role: "user" | "assistant"
  content: string
}

export type VoiceMood = "calm" | "fired_up" | "angry" | "smug" | "urgent"

export type VoicePlan = {
  shouldGenerate: boolean
  speakerId: string
  voiceLabel: string
  emoText: string
  emoVector: number[]
  emoAlpha: number
}

export type TTSResponse = {
  task_id?: string
  status?: string
  message?: string
  output_path?: string | null
  audio_url?: string | null
  duration?: number | null
}

export type TTSStatusResponse = {
  task_id?: string
  status?: string
  output_path?: string | null
  error_message?: string | null
  completed_at?: number | null
}
