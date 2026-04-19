import { defaultUsernames } from "./personas.ts"
import { resolveCostControls } from "./cost_controls.ts"

class MapEnv {
  constructor(private readonly values: Record<string, string>) {}

  get(key: string): string | undefined {
    return this.values[key]
  }
}

Deno.test("resolveCostControls defaults voice replies to disabled when unset", () => {
  const controls = resolveCostControls(new MapEnv({}))

  if (
    controls.llmGenerationMode !== "enabled" ||
    controls.ttsMode !== "disabled" ||
    controls.maxTTSCharacters !== 180 ||
    controls.messageImageMode !== "enabled" ||
    controls.xIngestMode !== "enabled" ||
    controls.maxXUsernamesPerRun !== defaultUsernames.length ||
    controls.maxXPostsPerUser !== 20
  ) {
    throw new Error("expected voice replies to default to disabled")
  }
})

Deno.test("resolveCostControls supports scoped overrides", () => {
  const controls = resolveCostControls(new MapEnv({
    BRUH_APP_ENV: "staging",
    BRUH_LLM_GENERATION_MODE__STAGING: "fallback_only",
    BRUH_TTS_MODE__STAGING: "force_only",
    BRUH_TTS_MAX_CHARACTERS__STAGING: "120",
    BRUH_MESSAGE_IMAGE_MODE__STAGING: "disabled",
    BRUH_X_INGEST_MODE__STAGING: "disabled",
    BRUH_X_INGEST_MAX_USERNAMES_PER_RUN__STAGING: "3",
    BRUH_X_INGEST_MAX_POSTS_PER_USER__STAGING: "4",
  }))

  if (
    controls.llmGenerationMode !== "fallback_only" ||
    controls.ttsMode !== "force_only" ||
    controls.maxTTSCharacters !== 120 ||
    controls.messageImageMode !== "disabled" ||
    controls.xIngestMode !== "disabled" ||
    controls.maxXUsernamesPerRun !== 3 ||
    controls.maxXPostsPerUser !== 4
  ) {
    throw new Error("expected scoped cost control overrides to apply")
  }
})

Deno.test("resolveCostControls clamps numeric limits into safe ranges", () => {
  const controls = resolveCostControls(new MapEnv({
    BRUH_TTS_MAX_CHARACTERS: "9999",
    BRUH_X_INGEST_MAX_USERNAMES_PER_RUN: "9999",
    BRUH_X_INGEST_MAX_POSTS_PER_USER: "0",
  }))

  if (
    controls.maxTTSCharacters !== 400 ||
    controls.maxXUsernamesPerRun !== defaultUsernames.length ||
    controls.maxXPostsPerUser !== 1
  ) {
    throw new Error("expected numeric controls to clamp into safe ranges")
  }
})

Deno.test("resolveCostControls rejects invalid enum values", () => {
  try {
    resolveCostControls(new MapEnv({
      BRUH_TTS_MODE: "sometimes",
    }))
    throw new Error("expected invalid enum error")
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error)
    if (!message.includes("BRUH_TTS_MODE")) {
      throw new Error(`unexpected error message: ${message}`)
    }
  }
})
