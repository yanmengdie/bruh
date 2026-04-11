import { getOptionalScopedEnv } from "./environment.ts"
import { allPersonaIds, resolvePersonaById } from "./personas.ts"

export type StarterSelectionStrategy = "balanced" | "global_only"
export type StarterImageMode = "adaptive" | "disabled"
export type StarterSourceUrlMode = "adaptive" | "always" | "never"
export type FeedReadSource = "auto" | "source_posts" | "feed_items"
export type FeedRankingStrategy = "chronological" | "importance"

type EnvReader = {
  get(key: string): string | undefined
}

export type BackendFeatureFlags = {
  enabledPersonaIds: string[]
  hasPersonaAllowlist: boolean
  starterSelectionStrategy: StarterSelectionStrategy
  starterImageMode: StarterImageMode
  starterSourceUrlMode: StarterSourceUrlMode
  feedReadSource: FeedReadSource
  feedRankingStrategy: FeedRankingStrategy
}

function parseStringList(value: string | undefined) {
  if (!value) return []

  return [...new Set(
    value
      .split(",")
      .map((item) => item.trim())
      .filter((item) => item.length > 0),
  )]
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

function resolveEnabledPersonaIds(env: EnvReader) {
  const configuredValue = getOptionalScopedEnv("BRUH_ENABLED_PERSONA_IDS", {
    env,
    aliases: ["BRUH_PERSONA_ALLOWLIST"],
  })
  const configuredIds = parseStringList(configuredValue)
  const availablePersonaIds = allPersonaIds()

  if (configuredIds.length === 0) {
    return {
      enabledPersonaIds: availablePersonaIds,
      hasPersonaAllowlist: false,
    }
  }

  const unknownPersonaIds = configuredIds.filter((personaId) => !resolvePersonaById(personaId))
  if (unknownPersonaIds.length > 0) {
    throw new Error(`Unknown persona ids in BRUH_ENABLED_PERSONA_IDS: ${unknownPersonaIds.join(", ")}.`)
  }

  const configuredSet = new Set(configuredIds)
  const enabledPersonaIds = availablePersonaIds.filter((personaId) => configuredSet.has(personaId))

  if (enabledPersonaIds.length === 0) {
    throw new Error("BRUH_ENABLED_PERSONA_IDS resolved to an empty persona set.")
  }

  return {
    enabledPersonaIds,
    hasPersonaAllowlist: true,
  }
}

export function resolveBackendFeatureFlags(env: EnvReader = Deno.env): BackendFeatureFlags {
  const personaConfig = resolveEnabledPersonaIds(env)

  return {
    ...personaConfig,
    starterSelectionStrategy: parseEnumValue(
      "BRUH_STARTER_SELECTION_STRATEGY",
      getOptionalScopedEnv("BRUH_STARTER_SELECTION_STRATEGY", { env }),
      ["balanced", "global_only"],
      "balanced",
    ),
    starterImageMode: parseEnumValue(
      "BRUH_STARTER_IMAGE_MODE",
      getOptionalScopedEnv("BRUH_STARTER_IMAGE_MODE", { env }),
      ["adaptive", "disabled"],
      "adaptive",
    ),
    starterSourceUrlMode: parseEnumValue(
      "BRUH_STARTER_SOURCE_URL_MODE",
      getOptionalScopedEnv("BRUH_STARTER_SOURCE_URL_MODE", { env }),
      ["adaptive", "always", "never"],
      "adaptive",
    ),
    feedReadSource: parseEnumValue(
      "BRUH_FEED_READ_SOURCE",
      getOptionalScopedEnv("BRUH_FEED_READ_SOURCE", { env }),
      ["auto", "source_posts", "feed_items"],
      "auto",
    ),
    feedRankingStrategy: parseEnumValue(
      "BRUH_FEED_RANKING_STRATEGY",
      getOptionalScopedEnv("BRUH_FEED_RANKING_STRATEGY", { env }),
      ["chronological", "importance"],
      "chronological",
    ),
  }
}
