import {
  getOptionalScopedEnv,
  getRequiredScopedEnv,
  getScopedEnvOrDefault,
  resolveDeploymentEnvironment,
  resolveSupabaseServiceConfig,
} from "./environment.ts"

class MapEnv {
  constructor(private readonly values: Record<string, string>) {}

  get(key: string): string | undefined {
    return this.values[key]
  }
}

Deno.test("resolveDeploymentEnvironment normalizes aliases", () => {
  const env = new MapEnv({ BRUH_APP_ENV: "stage" })
  if (resolveDeploymentEnvironment(env) !== "staging") {
    throw new Error("expected staging environment")
  }
})

Deno.test("getOptionalScopedEnv prefers environment-specific values", () => {
  const env = new MapEnv({
    BRUH_APP_ENV: "dev",
    OPENAI_MODEL: "global-model",
    OPENAI_MODEL__DEV: "dev-model",
  })

  const resolved = getOptionalScopedEnv("OPENAI_MODEL", { env })
  if (resolved !== "dev-model") {
    throw new Error(`expected dev-model, received ${resolved ?? "undefined"}`)
  }
})

Deno.test("getScopedEnvOrDefault falls back to global then default", () => {
  const env = new MapEnv({
    BRUH_APP_ENV: "prod",
    ANTHROPIC_BASE_URL: "https://example.com",
  })

  const resolved = getScopedEnvOrDefault("ANTHROPIC_BASE_URL", "https://fallback.example", { env })
  if (resolved !== "https://example.com") {
    throw new Error(`expected global fallback, received ${resolved}`)
  }
})

Deno.test("getRequiredScopedEnv reports scoped candidates", () => {
  const env = new MapEnv({ BRUH_APP_ENV: "dev" })

  try {
    getRequiredScopedEnv("PROJECT_URL", { env })
    throw new Error("expected missing env error")
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error)
    if (!message.includes("PROJECT_URL__DEV") || !message.includes("PROJECT_URL")) {
      throw new Error(`unexpected error message: ${message}`)
    }
  }
})

Deno.test("resolveSupabaseServiceConfig supports aliases", () => {
  const env = new MapEnv({
    BRUH_APP_ENV: "prod",
    SUPABASE_URL: "https://example.supabase.co",
    SUPABASE_SERVICE_ROLE_KEY: "test-role",
  })

  const config = resolveSupabaseServiceConfig(env)
  if (config.projectUrl !== "https://example.supabase.co" || config.serviceRoleKey !== "test-role") {
    throw new Error("expected alias-based Supabase config")
  }
})
