export type StarterEventRow = {
  id: string
  title: string
  summary: string
  category: string
  interest_tags: string[]
  representative_url: string | null
  global_rank: number | null
  is_global_top: boolean
  published_at: string
  importance_score: number
}

export type PersonaScoreRow = {
  event_id: string
  persona_id: string
  score: number
  reason_codes: string[] | null
  matched_interests: string[] | null
}

export type CandidateStarter = {
  event: StarterEventRow
  score: number
  selectionReasons: string[]
}

export type SelectedStarter = {
  event: StarterEventRow
  personaId: string
  score: number
  selectionReasons: string[]
}
