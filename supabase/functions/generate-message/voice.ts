import { getOptionalScopedEnv } from "../_shared/environment.ts"
import type { TTSMode } from "../_shared/cost_controls.ts"
import type { PersonaDefinition } from "../_shared/personas.ts"
import {
  approximateSpeechUnitCount,
  asString,
  clamp,
  countRegexMatches,
  countSignalHits,
  delay,
} from "./helpers.ts"
import type {
  TTSResponse,
  TTSStatusResponse,
  VoiceMood,
  VoicePlan,
} from "./types.ts"

const MAX_TTS_RETRIES = 2
const TTS_ASYNC_TIMEOUT_MS = 45_000
const TTS_ASYNC_SUBMIT_TIMEOUT_MS = 20_000
const TTS_STATUS_REQUEST_TIMEOUT_MS = 10_000
const TTS_STATUS_POLL_INTERVAL_MS = 1_000

export type VoiceReply = {
  audioUrl: string
  duration: number | null
  voiceLabel: string
}

function isConfiguredVoiceSpeakerId(speakerId: string) {
  const normalized = speakerId.trim()
  return /^upload:[a-f0-9]+$/i.test(normalized) || /^example:voice_(0[1-9]|1[0-2])$/i.test(normalized)
}

function resolveVoiceSpeakerId(persona: PersonaDefinition) {
  const overrideKey = `VOICE_SPEAKER_${persona.personaId.toUpperCase()}`
  return asString(getOptionalScopedEnv(overrideKey)) || persona.defaultVoiceSpeakerId
}

export function normalizeVoiceError(error: unknown) {
  const raw = error instanceof Error ? error.message : String(error)
  const trimmed = raw
    .replace(/^TTS request failed(?:\s*\(\d+\))?:\s*/i, "")
    .replace(/^Error:\s*/i, "")
    .trim()

  if (!trimmed) return "Voice synthesis failed"

  try {
    const payload = JSON.parse(trimmed) as Record<string, unknown>
    const detail = asString(payload.detail ?? payload.message ?? payload.error)
    if (detail) return detail
  } catch {
    // ignore malformed JSON and fall back to the raw text
  }

  return trimmed.length > 240 ? `${trimmed.slice(0, 237)}...` : trimmed
}

function classifyVoiceMood(content: string): VoiceMood {
  const lower = content.toLowerCase()
  const angerSignals = [
    "fake news",
    "lie",
    "liar",
    "disaster",
    "ridiculous",
    "离谱",
    "假的",
    "胡扯",
    "扯淡",
    "weak",
    "loser",
    "losers",
    "wrong",
    "stupid",
    "terrible",
  ]
  const smugSignals = [
    "believe me",
    "everyone knows",
    "obviously",
    "of course",
    "keep up",
    "i told you",
  ]
  const urgentSignals = [
    "now",
    "right now",
    "asap",
    "immediately",
    "today",
    "马上",
    "现在",
    "立刻",
    "move fast",
    "ship it",
    "accelerate",
  ]
  const firedUpSignals = [
    "huge",
    "massive",
    "crazy",
    "wild",
    "insane",
    "winning",
    "absolutely",
    "let's go",
    "lets go",
    "炸了",
    "太猛了",
  ]
  const exclamationCount = countRegexMatches(content, /[!！]/g)
  const uppercaseWordCount = countRegexMatches(content, /\b[A-Z]{3,}\b/g)
  const emojiCount = countRegexMatches(content, /[\p{Emoji_Presentation}\p{Extended_Pictographic}]/gu)
  const emphasisScore = clamp(exclamationCount, 0, 2) + clamp(uppercaseWordCount, 0, 1) + clamp(emojiCount, 0, 1)
  const angerHits = countSignalHits(lower, angerSignals)
  const smugHits = countSignalHits(lower, smugSignals)
  const urgentHits = countSignalHits(lower, urgentSignals)
  const firedUpHits = countSignalHits(lower, firedUpSignals)
  const totalMoodHits = angerHits + smugHits + urgentHits + firedUpHits

  if (angerHits >= 1 && (emphasisScore >= 1 || urgentHits >= 1 || totalMoodHits >= 2)) return "angry"
  if (urgentHits >= 2 || (urgentHits >= 1 && emphasisScore >= 1)) return "urgent"
  if (smugHits >= 2 || (smugHits >= 1 && emphasisScore >= 1)) return "smug"
  if (firedUpHits >= 2 || (firedUpHits >= 1 && emphasisScore >= 1) || emphasisScore >= 3 || totalMoodHits >= 3) {
    return "fired_up"
  }
  return "calm"
}

function voiceMoodVector(mood: VoiceMood) {
  switch (mood) {
    case "calm":
      return [0.12, 0.12, 0.08, 0.1, 0.08, 0.14, 0.12, 0.24]
    case "angry":
      return [0.08, 0.34, 0.05, 0.07, 0.12, 0.05, 0.08, 0.21]
    case "smug":
      return [0.22, 0.05, 0.03, 0.03, 0.02, 0.03, 0.16, 0.46]
    case "urgent":
      return [0.12, 0.14, 0.04, 0.12, 0.04, 0.03, 0.18, 0.33]
    case "fired_up":
    default:
      return [0.24, 0.1, 0.04, 0.04, 0.03, 0.03, 0.23, 0.29]
  }
}

function voiceMoodText(persona: PersonaDefinition, mood: VoiceMood) {
  switch (mood) {
    case "calm":
      return `${persona.displayName}, conversational, grounded, relaxed pace, natural pauses, calm confidence`
    case "angry":
      return `${persona.displayName}, firm and controlled, lightly frustrated, clipped delivery, strong conviction without shouting`
    case "smug":
      return `${persona.displayName}, dry confidence, lightly amused, relaxed control, understated swagger`
    case "urgent":
      return `${persona.displayName}, focused and direct, slightly faster pace, clear emphasis, controlled urgency`
    case "fired_up":
    default:
      return `${persona.displayName}, animated but conversational, clear momentum, confident emphasis, energized without yelling`
  }
}

function voiceMoodAlpha(mood: VoiceMood) {
  switch (mood) {
    case "calm":
      return 0.22
    case "smug":
      return 0.36
    case "urgent":
      return 0.44
    case "fired_up":
      return 0.5
    case "angry":
      return 0.56
    default:
      return 0.3
  }
}

function shouldReplyWithVoice(
  personaId: string,
  content: string,
  requestImage: boolean,
) {
  const trimmed = content.trim()
  if (requestImage || !trimmed) return false

  const approximateUnits = approximateSpeechUnitCount(trimmed)
  const minimumWordCount = personaId === "musk" ? 2 : 5
  if (approximateUnits < minimumWordCount || approximateUnits > 48 || trimmed.length > 180) return false

  const lower = trimmed.toLowerCase()
  const exclamationCount = countRegexMatches(trimmed, /[!！]/g)
  const uppercaseWordCount = countRegexMatches(trimmed, /\b[A-Z]{3,}\b/g)
  const emojiCount = countRegexMatches(trimmed, /[\p{Emoji_Presentation}\p{Extended_Pictographic}]/gu)
  const intenseSignalCount = [
    "huge",
    "massive",
    "crazy",
    "wild",
    "insane",
    "ridiculous",
    "离谱",
    "假的",
    "马上",
    "立刻",
    "fake news",
    "lie",
    "wrong",
    "winning",
    "believe me",
    "brutal",
    "disaster",
    "everyone knows",
    "move fast",
    "accelerate",
    "ship it",
    "absolutely",
  ].reduce((score, signal) => score + (lower.includes(signal) ? 1 : 0), 0)

  let score = 0
  score += clamp(exclamationCount, 0, 2)
  score += clamp(uppercaseWordCount, 0, 2)
  score += clamp(emojiCount, 0, 1)
  score += clamp(intenseSignalCount, 0, 3)

  if (personaId === "trump") score += 1
  if (personaId === "musk") score += 1
  if (/[?？]$/.test(trimmed) && exclamationCount === 0 && uppercaseWordCount === 0) score -= 1

  return score >= 2
}

export function buildVoicePlan(
  persona: PersonaDefinition,
  content: string,
  requestImage: boolean,
  forceVoice: boolean,
  options: {
    ttsMode?: TTSMode
    maxCharacters?: number
    automaticRepliesEnabled?: boolean
  } = {},
): VoicePlan {
  const ttsMode = options.ttsMode ?? "enabled"
  const maxCharacters = options.maxCharacters ?? 180
  const automaticRepliesEnabled = options.automaticRepliesEnabled ?? true
  const speakerId = resolveVoiceSpeakerId(persona)
  const trimmed = content.trim()
  const shouldGenerateVoice = ttsMode !== "disabled" &&
    (!requestImage) &&
    trimmed.length > 0 &&
    trimmed.length <= maxCharacters &&
    isConfiguredVoiceSpeakerId(speakerId) &&
    (forceVoice || (automaticRepliesEnabled && ttsMode !== "force_only" && shouldReplyWithVoice(persona.personaId, content, requestImage)))

  if (!shouldGenerateVoice) {
    return {
      shouldGenerate: false,
      speakerId: "",
      voiceLabel: "",
      emoText: "",
      emoVector: [],
      emoAlpha: 0,
    }
  }

  const mood = classifyVoiceMood(content)
  return {
    shouldGenerate: true,
    speakerId,
    voiceLabel: persona.defaultVoiceLabel,
    emoText: voiceMoodText(persona, mood),
    emoVector: voiceMoodVector(mood),
    emoAlpha: voiceMoodAlpha(mood),
  }
}

function buildAbsoluteVoiceUrl(baseUrl: string, relativeOrAbsoluteUrl: string, taskId: string) {
  const sanitizedBaseUrl = baseUrl.replace(/\/$/, "")
  if (/^https?:\/\//i.test(relativeOrAbsoluteUrl)) return relativeOrAbsoluteUrl
  const normalizedPath = relativeOrAbsoluteUrl
    ? relativeOrAbsoluteUrl.replace(/^\//, "")
    : `audio/${taskId}`
  return new URL(normalizedPath, `${sanitizedBaseUrl}/`).toString()
}

function buildVoiceRequestBody(plan: VoicePlan, content: string) {
  return {
    text: content,
    speaker_id: plan.speakerId,
    use_emo_text: true,
    emo_text: plan.emoText,
    emo_vector: plan.emoVector,
    emo_alpha: plan.emoAlpha,
    max_text_tokens_per_segment: 120,
    top_p: 0.78,
    top_k: 30,
    temperature: 0.72,
    repetition_penalty: 6,
  }
}

function isVoiceTimeoutError(error: unknown) {
  const message = error instanceof Error ? error.message : String(error)
  return /signal timed out|aborted|timeout/i.test(message)
}

async function synthesizeVoiceReplyAsync(
  voiceApiBaseUrl: string,
  voiceApiKey: string | null,
  plan: VoicePlan,
  content: string,
): Promise<VoiceReply> {
  const headers: Record<string, string> = {
    "Content-Type": "application/json",
    ...(voiceApiKey ? { Authorization: `Bearer ${voiceApiKey}` } : {}),
  }

  const submitResponse = await fetch(`${voiceApiBaseUrl}/tts/async`, {
    method: "POST",
    headers,
    body: JSON.stringify(buildVoiceRequestBody(plan, content)),
    signal: AbortSignal.timeout(TTS_ASYNC_SUBMIT_TIMEOUT_MS),
  })

  if (!submitResponse.ok) {
    const responseText = (await submitResponse.text()).trim()
    throw new Error(
      responseText
        ? `TTS async request failed (${submitResponse.status}): ${responseText}`
        : `TTS async request failed (${submitResponse.status})`,
    )
  }

  const submitted = await submitResponse.json() as TTSResponse
  const taskId = asString(submitted.task_id)
  if (!taskId) {
    throw new Error("TTS async response missing task_id")
  }

  const deadline = Date.now() + TTS_ASYNC_TIMEOUT_MS
  while (Date.now() < deadline) {
    await delay(TTS_STATUS_POLL_INTERVAL_MS)

    const statusResponse = await fetch(`${voiceApiBaseUrl}/tts/status/${taskId}`, {
      method: "GET",
      headers: voiceApiKey ? { Authorization: `Bearer ${voiceApiKey}` } : undefined,
      signal: AbortSignal.timeout(TTS_STATUS_REQUEST_TIMEOUT_MS),
    })

    if (!statusResponse.ok) {
      const responseText = (await statusResponse.text()).trim()
      throw new Error(
        responseText
          ? `TTS status request failed (${statusResponse.status}): ${responseText}`
          : `TTS status request failed (${statusResponse.status})`,
      )
    }

    const statusPayload = await statusResponse.json() as TTSStatusResponse
    const status = asString(statusPayload.status)
    if (status === "completed") {
      return {
        audioUrl: buildAbsoluteVoiceUrl(voiceApiBaseUrl, "", taskId),
        duration: null,
        voiceLabel: plan.voiceLabel,
      }
    }

    if (status === "failed") {
      throw new Error(asString(statusPayload.error_message) || "TTS async task failed")
    }
  }

  throw new Error("TTS async polling timed out")
}

export async function synthesizeVoiceReplyWithRetries(
  voiceApiBaseUrl: string,
  voiceApiKey: string | null,
  plan: VoicePlan,
  content: string,
  forceVoice: boolean,
): Promise<VoiceReply> {
  let lastError: unknown = null
  const attemptCount = forceVoice ? MAX_TTS_RETRIES : 1

  for (let attempt = 1; attempt <= attemptCount; attempt += 1) {
    try {
      return await synthesizeVoiceReplyAsync(
        voiceApiBaseUrl,
        voiceApiKey,
        plan,
        content,
      )
    } catch (error) {
      lastError = error
      if (attempt < attemptCount && (forceVoice || isVoiceTimeoutError(error))) {
        await delay(200 * attempt)
      }
    }
  }

  throw (lastError instanceof Error ? lastError : new Error(String(lastError ?? "Voice synthesis failed")))
}
