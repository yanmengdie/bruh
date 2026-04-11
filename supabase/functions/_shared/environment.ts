export type DeploymentEnvironment = "dev" | "staging" | "prod"

type EnvReader = {
  get(key: string): string | undefined
}

function normalizeEnvironment(value: string | undefined): DeploymentEnvironment | null {
  switch (value?.trim().toLowerCase()) {
    case "dev":
    case "development":
    case "local":
    case "debug":
      return "dev"
    case "staging":
    case "stage":
    case "stg":
    case "qa":
    case "test":
      return "staging"
    case "prod":
    case "production":
    case "release":
    case "live":
      return "prod"
    default:
      return null
  }
}

function firstNonEmpty(env: EnvReader, keys: string[]): string | undefined {
  for (const key of keys) {
    const value = env.get(key)?.trim()
    if (value) return value
  }
  return undefined
}

function scopedKeys(baseKeys: string[], deploymentEnvironment: DeploymentEnvironment): string[] {
  const keys: string[] = []
  const seen = new Set<string>()
  const suffix = deploymentEnvironment.toUpperCase()

  for (const key of baseKeys) {
    const scopedKey = `${key}__${suffix}`
    if (seen.has(scopedKey)) continue
    seen.add(scopedKey)
    keys.push(scopedKey)
  }

  for (const key of baseKeys) {
    if (seen.has(key)) continue
    seen.add(key)
    keys.push(key)
  }

  return keys
}

export function resolveDeploymentEnvironment(env: EnvReader = Deno.env): DeploymentEnvironment {
  return normalizeEnvironment(firstNonEmpty(env, ["BRUH_APP_ENV", "BRUH_ENV", "DEPLOY_ENV", "ENVIRONMENT"])) ?? "prod"
}

export function getOptionalScopedEnv(
  key: string,
  options: {
    env?: EnvReader
    deploymentEnvironment?: DeploymentEnvironment
    aliases?: string[]
  } = {},
): string | undefined {
  const env = options.env ?? Deno.env
  const deploymentEnvironment = options.deploymentEnvironment ?? resolveDeploymentEnvironment(env)
  return firstNonEmpty(env, scopedKeys([key, ...(options.aliases ?? [])], deploymentEnvironment))
}

export function getScopedEnvOrDefault(
  key: string,
  defaultValue: string,
  options: {
    env?: EnvReader
    deploymentEnvironment?: DeploymentEnvironment
    aliases?: string[]
  } = {},
): string {
  return getOptionalScopedEnv(key, options) ?? defaultValue
}

export function getRequiredScopedEnv(
  key: string,
  options: {
    env?: EnvReader
    deploymentEnvironment?: DeploymentEnvironment
    aliases?: string[]
  } = {},
): string {
  const env = options.env ?? Deno.env
  const deploymentEnvironment = options.deploymentEnvironment ?? resolveDeploymentEnvironment(env)
  const candidates = scopedKeys([key, ...(options.aliases ?? [])], deploymentEnvironment)
  const value = firstNonEmpty(env, candidates)
  if (value) return value

  throw new Error(`Missing environment variable ${key}. Looked for ${candidates.join(", ")}.`)
}

export function resolveSupabaseServiceConfig(env: EnvReader = Deno.env) {
  const deploymentEnvironment = resolveDeploymentEnvironment(env)

  return {
    deploymentEnvironment,
    projectUrl: getRequiredScopedEnv("PROJECT_URL", {
      env,
      deploymentEnvironment,
      aliases: ["SUPABASE_URL"],
    }),
    serviceRoleKey: getRequiredScopedEnv("SERVICE_ROLE_KEY", {
      env,
      deploymentEnvironment,
      aliases: ["SUPABASE_SERVICE_ROLE_KEY"],
    }),
  }
}
