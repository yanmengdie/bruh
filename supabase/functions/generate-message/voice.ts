import { getOptionalScopedEnv } from "../_shared/environment.ts"
import type { TTSMode } from "../_shared/cost_controls.ts"
import type { PersonaDefinition } from "../_shared/personas.ts"
import {
  approximateSpeechUnitCount,
  asString,
  clamp,
  countRegexMatches,
} from "./helpers.ts"
import type { VoicePlan } from "./types.ts"

const TTS_REQUEST_TIMEOUT_MS = 30_000

export type VoiceReply = {
  audioUrl: string
  duration: number | null
  voiceLabel: string
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
    "huge", "massive", "crazy", "wild", "insane", "ridiculous", "离谱", "假的", "马上", "立刻",
    "fake news", "lie", "wrong", "winning", "believe me", "brutal", "disaster", "everyone knows",
    "move fast", "accelerate", "ship it", "absolutely",
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
  const shouldGenerate = ttsMode !== "disabled" &&
    !requestImage &&
    trimmed.length > 0 &&
    trimmed.length <= maxCharacters &&
    speakerId.startsWith("data:audio/") &&
    (forceVoice || (automaticRepliesEnabled && ttsMode !== "force_only" && shouldReplyWithVoice(persona.personaId, content, requestImage)))

  return {
    shouldGenerate,
    speakerId: shouldGenerate ? speakerId : "",
    voiceLabel: shouldGenerate ? persona.defaultVoiceLabel : "",
  }
}

async function synthesizeVoiceReply(
  voiceApiBaseUrl: string,
  voiceApiKey: string | null,
  plan: VoicePlan,
  content: string,
): Promise<VoiceReply> {
  const headers: Record<string, string> = {
    "Content-Type": "application/json",
    ...(voiceApiKey ? { "api-key": voiceApiKey } : {}),
  }

  const response = await fetch(`${voiceApiBaseUrl}/chat/completions`, {
    method: "POST",
    headers,
    body: JSON.stringify({
      model: "mimo-v2.5-tts-voiceclone",
      messages: [
        { role: "user", content: "" },
        { role: "assistant", content },
      ],
      audio: { format: "wav", voice: plan.speakerId },
      stream: false,
    }),
    signal: AbortSignal.timeout(TTS_REQUEST_TIMEOUT_MS),
  })

  if (!response.ok) {
    const responseText = (await response.text()).trim()
    throw new Error(
      responseText
        ? `TTS request failed (${response.status}): ${responseText}`
        : `TTS request failed (${response.status})`,
    )
  }

  const result = await response.json()
  const audioData = result.choices?.[0]?.message?.audio?.data

  if (!audioData) {
    throw new Error("TTS response missing audio data")
  }

  const audioBytes = Uint8Array.from(atob(audioData), c => c.charCodeAt(0))
  const audioBlob = new Blob([audioBytes], { type: "audio/wav" })
  const audioUrl = URL.createObjectURL(audioBlob)

  return {
    audioUrl,
    duration: null,
    voiceLabel: plan.voiceLabel,
  }
}

export async function synthesizeVoiceReplyWithRetries(
  voiceApiBaseUrl: string,
  voiceApiKey: string | null,
  plan: VoicePlan,
  content: string,
  forceVoice: boolean,
): Promise<VoiceReply> {
  let lastError: unknown = null
  const attemptCount = forceVoice ? 2 : 1

  for (let attempt = 1; attempt <= attemptCount; attempt += 1) {
    try {
      return await synthesizeVoiceReply(voiceApiBaseUrl, voiceApiKey, plan, content)
    } catch (error) {
      lastError = error
      if (attempt < attemptCount) {
        await new Promise(resolve => setTimeout(resolve, 200 * attempt))
      }
    }
  }

  throw (lastError instanceof Error ? lastError : new Error(String(lastError ?? "Voice synthesis failed")))
}
