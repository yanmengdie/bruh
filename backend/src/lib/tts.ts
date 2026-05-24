import { resolveVoiceSampleDataUrl } from "./personas.js"
import type { VoicePlan } from "../types.js"

const VOICE_API_KEY = process.env.VOICE_API_KEY || null
const VOICE_API_BASE_URL = process.env.VOICE_API_BASE_URL || null
const TTS_TIMEOUT_MS = 30_000

export function buildVoicePlan(
  personaId: string,
  content: string,
  forceVoice: boolean,
  ttsMode: string = "enabled",
): VoicePlan {
  const trimmed = content.trim()
  if (ttsMode === "disabled" || !trimmed || trimmed.length > 180) {
    return { shouldGenerate: false, speakerId: "", voiceLabel: "" }
  }

  const speakerId = resolveVoiceSampleDataUrl(personaId)
  if (!speakerId) return { shouldGenerate: false, speakerId: "", voiceLabel: "" }

  // Simple heuristic: generate voice if forced or if content has emotional signals
  const hasEmotion = /[!！]/.test(trimmed) || /\b[A-Z]{3,}\b/.test(trimmed)
  if (!forceVoice && ttsMode !== "enabled") return { shouldGenerate: false, speakerId: "", voiceLabel: "" }
  if (!forceVoice && !hasEmotion) return { shouldGenerate: false, speakerId: "", voiceLabel: "" }

  return { shouldGenerate: true, speakerId, voiceLabel: `${personaId} voice` }
}

export async function synthesizeVoice(
  plan: VoicePlan,
  content: string,
): Promise<{ audioUrl: string; duration: number | null } | null> {
  if (!plan.shouldGenerate || !VOICE_API_BASE_URL) return null

  const headers: Record<string, string> = {
    "Content-Type": "application/json",
    ...(VOICE_API_KEY ? { "api-key": VOICE_API_KEY } : {}),
  }

  try {
    const response = await fetch(`${VOICE_API_BASE_URL}/chat/completions`, {
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
      signal: AbortSignal.timeout(TTS_TIMEOUT_MS),
    })

    if (!response.ok) {
      console.error(`TTS failed: ${response.status} ${await response.text()}`)
      return null
    }

    const result = await response.json()
    const audioData = result.choices?.[0]?.message?.audio?.data
    if (!audioData) return null

    const audioBytes = Buffer.from(audioData, "base64")
    const audioUrl = `data:audio/wav;base64,${audioBytes.toString("base64")}`

    return { audioUrl, duration: null }
  } catch (error) {
    console.error("TTS error:", error)
    return null
  }
}
