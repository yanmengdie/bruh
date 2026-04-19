import type { SupabaseClient } from "jsr:@supabase/supabase-js@2";
import {
  type DeploymentEnvironment,
  resolveDeploymentEnvironment,
} from "../supabase/functions/_shared/environment.ts";
import {
  type BackendHealthSnapshot,
  collectBackendHealthSnapshot,
  type HealthLevel,
} from "./backend_health_snapshot_lib.ts";

type EnvReader = {
  get(key: string): string | undefined;
};

type EnvRequirement = {
  name: string;
  description: string;
  required: boolean;
  keys: string[];
};

const envRequirements: EnvRequirement[] = [
  {
    name: "Supabase URL",
    description: "service-role project endpoint",
    required: true,
    keys: ["PROJECT_URL", "SUPABASE_URL"],
  },
  {
    name: "Supabase service role",
    description: "backend function and operator access",
    required: true,
    keys: ["SERVICE_ROLE_KEY", "SUPABASE_SERVICE_ROLE_KEY"],
  },
  {
    name: "Functions base URL",
    description: "client routing to Edge Functions",
    required: true,
    keys: ["BRUH_FUNCTIONS_BASE_URL", "SUPABASE_FUNCTIONS_BASE_URL"],
  },
  {
    name: "Supabase anon key",
    description: "client publishable key",
    required: true,
    keys: ["BRUH_SUPABASE_ANON_KEY", "SUPABASE_ANON_KEY"],
  },
  {
    name: "LLM provider",
    description: "persona reply, starter, and interaction generation",
    required: false,
    keys: ["OPENAI_API_KEY"],
  },
  {
    name: "Nano Banana",
    description: "message and starter image generation",
    required: false,
    keys: ["NANO_BANANA_API_KEY"],
  },
  {
    name: "Voice provider",
    description: "async voice reply generation",
    required: false,
    keys: ["VOICE_API_KEY"],
  },
];

const criticalTables = [
  "pipeline_job_locks",
  "news_articles",
  "news_events",
  "persona_news_scores",
  "feed_items",
  "source_posts",
] as const;

export type PreflightLevel = "pass" | "warn" | "fail";

export type ReleasePreflightEnvCheck = {
  name: string;
  description: string;
  required: boolean;
  level: PreflightLevel;
  foundKey: string | null;
  summary: string;
};

export type ReleasePreflightTableCheck = {
  name: string;
  level: PreflightLevel;
  rowCount: number | null;
  summary: string;
};

export type ReleasePreflightSnapshot = {
  checkedAt: string;
  environment: DeploymentEnvironment;
  projectHost: string | null;
  overallLevel: PreflightLevel;
  envChecks: ReleasePreflightEnvCheck[];
  tableChecks: ReleasePreflightTableCheck[];
  health: BackendHealthSnapshot | null;
};

function scopedCandidateKeys(
  baseKeys: string[],
  deploymentEnvironment: DeploymentEnvironment,
) {
  const suffix = deploymentEnvironment.toUpperCase();
  const seen = new Set<string>();
  const candidates: string[] = [];

  for (const key of baseKeys) {
    const scoped = `${key}__${suffix}`;
    if (seen.has(scoped)) continue;
    seen.add(scoped);
    candidates.push(scoped);
  }

  for (const key of baseKeys) {
    if (seen.has(key)) continue;
    seen.add(key);
    candidates.push(key);
  }

  return candidates;
}

function resolveEnvValue(
  env: EnvReader,
  keys: string[],
  deploymentEnvironment: DeploymentEnvironment,
) {
  for (const key of scopedCandidateKeys(keys, deploymentEnvironment)) {
    const value = env.get(key)?.trim();
    if (value) {
      return { key, value };
    }
  }

  return null;
}

function projectHost(projectUrl: string | null) {
  if (!projectUrl) return null;
  try {
    return new URL(projectUrl).host;
  } catch {
    return projectUrl;
  }
}

function healthLevelToPreflight(level: HealthLevel | null): PreflightLevel {
  if (level === null) return "fail";
  return ["healthy", "running"].includes(level) ? "pass" : "fail";
}

export function resolvePreflightEnvChecks(
  env: EnvReader,
  deploymentEnvironment = resolveDeploymentEnvironment(env),
): ReleasePreflightEnvCheck[] {
  const checks = envRequirements.map((requirement) => {
    const resolved = resolveEnvValue(
      env,
      requirement.keys,
      deploymentEnvironment,
    );
    if (resolved) {
      return {
        name: requirement.name,
        description: requirement.description,
        required: requirement.required,
        level: "pass",
        foundKey: resolved.key,
        summary: `resolved from ${resolved.key}`,
      } satisfies ReleasePreflightEnvCheck;
    }

    const candidates = scopedCandidateKeys(
      requirement.keys,
      deploymentEnvironment,
    ).join(", ");

    return {
      name: requirement.name,
      description: requirement.description,
      required: requirement.required,
      level: requirement.required ? "fail" : "warn",
      foundKey: null,
      summary: requirement.required
        ? `missing; looked for ${candidates}`
        : `optional; not configured (${candidates})`,
    } satisfies ReleasePreflightEnvCheck;
  });

  const ingestProviderConfig = resolveEnvValue(
    env,
    ["BRUH_X_INGEST_PROVIDER"],
    deploymentEnvironment,
  );
  const ingestProvider = ingestProviderConfig?.value?.trim().toLowerCase() ??
    "self_hosted_service";

  const supportedProviders = new Set([
    "self_hosted",
    "self-hosted",
    "self_hosted_service",
    "self-hosted-service",
    "selfhosted",
  ]);

  checks.push(supportedProviders.has(ingestProvider)
    ? {
      name: "X ingest provider",
      description: "active X ingestion backend",
      required: false,
      level: "pass",
      foundKey: ingestProviderConfig?.key ?? "default:self_hosted_service",
      summary: "resolved to self_hosted_service",
    }
    : {
      name: "X ingest provider",
      description: "active X ingestion backend",
      required: false,
      level: "fail",
      foundKey: null,
      summary:
        `unsupported provider '${ingestProvider}'; expected self_hosted_service`,
    });

  const serviceUrl = resolveEnvValue(
    env,
    [
      "BRUH_X_SELF_HOSTED_SERVICE_URL",
      "X_INGEST_SERVICE_URL",
      "BRUH_X_SCRAPER_SERVICE_URL",
    ],
    deploymentEnvironment,
  );
  checks.push(serviceUrl
    ? {
      name: "Self-hosted X ingest service",
      description: "local crawler service URL for X ingestion",
      required: false,
      level: "pass",
      foundKey: serviceUrl.key,
      summary: `resolved from ${serviceUrl.key}`,
    }
    : {
      name: "Self-hosted X ingest service",
      description: "local crawler service URL for X ingestion",
      required: false,
      level: "warn",
      foundKey: null,
      summary:
        "optional; not configured (BRUH_X_SELF_HOSTED_SERVICE_URL / X_INGEST_SERVICE_URL / BRUH_X_SCRAPER_SERVICE_URL)",
    });

  return checks;
}

async function probeCriticalTable(
  supabase: SupabaseClient,
  table: string,
): Promise<ReleasePreflightTableCheck> {
  const { count, error } = await supabase
    .from(table)
    .select("*", { count: "exact", head: true });

  if (error) {
    return {
      name: table,
      level: "fail",
      rowCount: null,
      summary: `probe failed: ${error.message}`,
    };
  }

  return {
    name: table,
    level: "pass",
    rowCount: count ?? 0,
    summary: `reachable with ${count ?? 0} rows`,
  };
}

export function overallPreflightLevel(snapshot: {
  envChecks: Array<{ level: PreflightLevel }>;
  tableChecks: Array<{ level: PreflightLevel }>;
  health: BackendHealthSnapshot | null;
}): PreflightLevel {
  if (
    snapshot.envChecks.some((check) => check.level === "fail") ||
    snapshot.tableChecks.some((check) => check.level === "fail") ||
    healthLevelToPreflight(snapshot.health?.overallLevel ?? null) === "fail"
  ) {
    return "fail";
  }

  if (snapshot.envChecks.some((check) => check.level === "warn")) {
    return "warn";
  }

  return "pass";
}

export async function collectReleasePreflightSnapshot(
  supabase: SupabaseClient | null,
  options: {
    env?: EnvReader;
    deploymentEnvironment?: DeploymentEnvironment;
    now?: Date;
    projectUrl?: string | null;
  } = {},
): Promise<ReleasePreflightSnapshot> {
  const env = options.env ?? Deno.env;
  const deploymentEnvironment = options.deploymentEnvironment ??
    resolveDeploymentEnvironment(env);
  const checkedAt = (options.now ?? new Date()).toISOString();
  const envChecks = resolvePreflightEnvChecks(env, deploymentEnvironment);
  const projectUrl = options.projectUrl ??
    resolveEnvValue(env, ["PROJECT_URL", "SUPABASE_URL"], deploymentEnvironment)
      ?.value ??
    null;

  const tableChecks = supabase
    ? await Promise.all(
      criticalTables.map((table) => probeCriticalTable(supabase, table)),
    )
    : criticalTables.map((table) =>
      ({
        name: table,
        level: "fail",
        rowCount: null,
        summary: "skipped because Supabase credentials are missing",
      }) satisfies ReleasePreflightTableCheck
    );

  let health: BackendHealthSnapshot | null = null;
  if (supabase) {
    try {
      health = await collectBackendHealthSnapshot(supabase, {
        environment: deploymentEnvironment,
        projectUrl: projectUrl ?? "unknown",
        now: options.now,
      });
    } catch {
      health = null;
    }
  }

  return {
    checkedAt,
    environment: deploymentEnvironment,
    projectHost: projectHost(projectUrl),
    overallLevel: overallPreflightLevel({ envChecks, tableChecks, health }),
    envChecks,
    tableChecks,
    health,
  };
}

export function formatReleasePreflight(
  snapshot: ReleasePreflightSnapshot,
): string {
  const lines = [
    `Environment: ${snapshot.environment}`,
    `Project: ${snapshot.projectHost ?? "unknown"}`,
    `Checked at: ${snapshot.checkedAt}`,
    `Overall: ${snapshot.overallLevel}`,
    `Backend health: ${snapshot.health?.overallLevel ?? "not_checked"}`,
    "",
    "Environment checks:",
    ...snapshot.envChecks.map((check) =>
      `- [${check.level}] ${check.name}: ${check.summary}`
    ),
    "",
    "Critical tables:",
    ...snapshot.tableChecks.map((check) =>
      `- [${check.level}] ${check.name}: ${check.summary}`
    ),
  ];

  if (snapshot.health) {
    lines.push(
      "",
      "Health summary:",
      ...snapshot.health.jobs.map((job) =>
        `- [${job.level}] job ${job.name}: ${job.summary}`
      ),
      ...snapshot.health.tables.map((table) =>
        `- [${table.level}] table ${table.name}: ${table.summary}`
      ),
    );
  }

  return lines.join("\n");
}
