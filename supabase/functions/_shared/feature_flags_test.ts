import { allPersonaIds } from "./personas.ts"
import { resolveBackendFeatureFlags } from "./feature_flags.ts"

class MapEnv {
  constructor(private readonly values: Record<string, string>) {}

  get(key: string): string | undefined {
    return this.values[key]
  }
}

Deno.test("resolveBackendFeatureFlags preserves current defaults when unset", () => {
  const flags = resolveBackendFeatureFlags(new MapEnv({}))

  if (flags.enabledPersonaIds.length !== allPersonaIds().length) {
    throw new Error("expected all personas to stay enabled by default")
  }

  if (
    flags.starterSelectionStrategy !== "balanced" ||
    flags.starterImageMode !== "adaptive" ||
    flags.starterSourceUrlMode !== "adaptive" ||
    flags.feedReadSource !== "auto" ||
    flags.feedRankingStrategy !== "chronological"
  ) {
    throw new Error("expected default feature flags to preserve current behavior")
  }
})

Deno.test("resolveBackendFeatureFlags supports scoped rollout overrides", () => {
  const flags = resolveBackendFeatureFlags(new MapEnv({
    BRUH_APP_ENV: "staging",
    BRUH_ENABLED_PERSONA_IDS__STAGING: "musk, sam_altman",
    BRUH_STARTER_SELECTION_STRATEGY__STAGING: "global_only",
    BRUH_STARTER_IMAGE_MODE__STAGING: "disabled",
    BRUH_STARTER_SOURCE_URL_MODE__STAGING: "always",
    BRUH_FEED_READ_SOURCE__STAGING: "feed_items",
    BRUH_FEED_RANKING_STRATEGY__STAGING: "importance",
  }))

  if (flags.enabledPersonaIds.join(",") !== "musk,sam_altman") {
    throw new Error(`unexpected enabled personas: ${flags.enabledPersonaIds.join(",")}`)
  }

  if (!flags.hasPersonaAllowlist) {
    throw new Error("expected rollout allowlist to be marked as configured")
  }

  if (
    flags.starterSelectionStrategy !== "global_only" ||
    flags.starterImageMode !== "disabled" ||
    flags.starterSourceUrlMode !== "always" ||
    flags.feedReadSource !== "feed_items" ||
    flags.feedRankingStrategy !== "importance"
  ) {
    throw new Error("expected scoped feature flag overrides to be applied")
  }
})

Deno.test("resolveBackendFeatureFlags rejects unknown persona ids", () => {
  try {
    resolveBackendFeatureFlags(new MapEnv({
      BRUH_ENABLED_PERSONA_IDS: "musk,unknown_persona",
    }))
    throw new Error("expected unknown persona validation error")
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error)
    if (!message.includes("unknown_persona")) {
      throw new Error(`unexpected error message: ${message}`)
    }
  }
})

Deno.test("resolveBackendFeatureFlags rejects invalid enum values", () => {
  try {
    resolveBackendFeatureFlags(new MapEnv({
      BRUH_STARTER_SELECTION_STRATEGY: "surprise-me",
    }))
    throw new Error("expected invalid enum error")
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error)
    if (!message.includes("BRUH_STARTER_SELECTION_STRATEGY")) {
      throw new Error(`unexpected error message: ${message}`)
    }
  }
})
