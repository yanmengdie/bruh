import { getOptionalScopedEnv } from "./environment.ts"
import { defaultUsernames } from "./personas.ts"

export type LLMGenerationMode = "enabled" | "fallback_only"
export type TTSMode = "enabled" | "force_only" | "disabled"
export type BinaryGenerationMode = "enabled" | "disabled"
export type XIngestMode = "enabled" | "disabled"

type EnvReader = {
  get(key: string): string | undefined
}

export type CostControls = {
  llmGenerationMode: LLMGenerationMode
  ttsMode: TTSMode
  maxTTSCharacters: number
  messageImageMode: BinaryGenerationMode
  xIngestMode: XIngestMode
  maxXUsernamesPerRun: number
  maxXPostsPerUser: number
}

function parseEnumValue<T extends string>(
  label: string,
  value: string | undefined,
  allowedValues: readonly T[],
  defaultValue: T,
): T {
  if (!value) return defaultValue

  const normalized = value.trim().toLowerCase()
  const match = allowedValues.find((candidate) => candidate === normalized)
  if (match) return match

  throw new Error(`Invalid ${label}: ${value}. Expected one of ${allowedValues.join(", ")}.`)
}

function parseInteger(
  label: string,
  value: string | undefined,
  defaultValue: number,
  min: number,
  max: number,
) {
  if (!value) return defaultValue

  const parsed = Number.parseInt(value.trim(), 10)
  if (Number.isNaN(parsed)) {
    throw new Error(`Invalid ${label}: ${value}. Expected an integer.`)
  }

  return Math.min(Math.max(parsed, min), max)
}

export function resolveCostControls(env: EnvReader = Deno.env): CostControls {
  return {
    llmGenerationMode: parseEnumValue(
      "BRUH_LLM_GENERATION_MODE",
      getOptionalScopedEnv("BRUH_LLM_GENERATION_MODE", { env }),
      ["enabled", "fallback_only"],
      "enabled",
    ),
    ttsMode: parseEnumValue(
      "BRUH_TTS_MODE",
      getOptionalScopedEnv("BRUH_TTS_MODE", { env }),
      ["enabled", "force_only", "disabled"],
      "enabled",
    ),
    maxTTSCharacters: parseInteger(
      "BRUH_TTS_MAX_CHARACTERS",
      getOptionalScopedEnv("BRUH_TTS_MAX_CHARACTERS", { env }),
      180,
      40,
      400,
    ),
    messageImageMode: parseEnumValue(
      "BRUH_MESSAGE_IMAGE_MODE",
      getOptionalScopedEnv("BRUH_MESSAGE_IMAGE_MODE", { env }),
      ["enabled", "disabled"],
      "enabled",
    ),
    xIngestMode: parseEnumValue(
      "BRUH_X_INGEST_MODE",
      getOptionalScopedEnv("BRUH_X_INGEST_MODE", { env }),
      ["enabled", "disabled"],
      "enabled",
    ),
    maxXUsernamesPerRun: parseInteger(
      "BRUH_X_INGEST_MAX_USERNAMES_PER_RUN",
      getOptionalScopedEnv("BRUH_X_INGEST_MAX_USERNAMES_PER_RUN", { env }),
      Math.max(defaultUsernames.length, 1),
      1,
      Math.max(defaultUsernames.length, 1),
    ),
    maxXPostsPerUser: parseInteger(
      "BRUH_X_INGEST_MAX_POSTS_PER_USER",
      getOptionalScopedEnv("BRUH_X_INGEST_MAX_POSTS_PER_USER", { env }),
      20,
      1,
      20,
    ),
  }
}
