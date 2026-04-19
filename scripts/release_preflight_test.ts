import {
  formatReleasePreflight,
  overallPreflightLevel,
  resolvePreflightEnvChecks,
} from "./release_preflight_lib.ts";

function envReader(values: Record<string, string>) {
  return {
    get(key: string) {
      return values[key];
    },
  };
}

Deno.test("resolvePreflightEnvChecks prefers scoped values and warns on optional gaps", () => {
  const checks = resolvePreflightEnvChecks(
    envReader({
      PROJECT_URL__STAGING: "https://example.supabase.co",
      SERVICE_ROLE_KEY__STAGING: "service-role",
      BRUH_FUNCTIONS_BASE_URL__STAGING:
        "https://example.supabase.co/functions/v1",
      BRUH_SUPABASE_ANON_KEY__STAGING: "anon",
    }),
    "staging",
  );

  const supabaseUrl = checks.find((check) => check.name === "Supabase URL");
  if (supabaseUrl?.foundKey !== "PROJECT_URL__STAGING") {
    throw new Error("expected scoped Supabase URL to be preferred");
  }

  const llmProvider = checks.find((check) => check.name === "LLM provider");
  if (llmProvider?.level !== "warn") {
    throw new Error("expected optional LLM provider to warn when missing");
  }
});

Deno.test("resolvePreflightEnvChecks switches X ingest warning based on provider", () => {
  const checks = resolvePreflightEnvChecks(
    envReader({
      PROJECT_URL__PROD: "http://127.0.0.1:3000",
      SERVICE_ROLE_KEY__PROD: "service-role",
      BRUH_FUNCTIONS_BASE_URL__PROD: "https://api.example.com/functions/v1",
      BRUH_SUPABASE_ANON_KEY__PROD: "anon",
      BRUH_X_INGEST_PROVIDER__PROD: "self_hosted_service",
      BRUH_X_SELF_HOSTED_SERVICE_URL__PROD: "http://127.0.0.1:8789/fetch",
    }),
    "prod",
  );

  const selfHostedService = checks.find((check) =>
    check.name === "Self-hosted X ingest service"
  );
  if (selfHostedService?.level !== "pass") {
    throw new Error("expected self-hosted X ingest service to pass");
  }

  const apifyToken = checks.find((check) => check.name === "Apify token");
  if (apifyToken) {
    throw new Error("expected Apify token check to be omitted in self-hosted mode");
  }
});

Deno.test("overallPreflightLevel fails on unhealthy backend state", () => {
  const level = overallPreflightLevel({
    envChecks: [{ level: "pass" }],
    tableChecks: [{ level: "pass" }],
    health: {
      checkedAt: "2026-04-12T10:00:00Z",
      environment: "prod",
      projectHost: "example.supabase.co",
      overallLevel: "stale",
      jobs: [],
      tables: [],
    },
  });

  if (level !== "fail") {
    throw new Error(`expected fail, got ${level}`);
  }
});

Deno.test("formatReleasePreflight renders status sections", () => {
  const text = formatReleasePreflight({
    checkedAt: "2026-04-12T10:00:00Z",
    environment: "prod",
    projectHost: "example.supabase.co",
    overallLevel: "pass",
    envChecks: [{
      name: "Supabase URL",
      description: "service-role project endpoint",
      required: true,
      level: "pass",
      foundKey: "PROJECT_URL__PROD",
      summary: "resolved from PROJECT_URL__PROD",
    }],
    tableChecks: [{
      name: "feed_items",
      level: "pass",
      rowCount: 20,
      summary: "reachable with 20 rows",
    }],
    health: {
      checkedAt: "2026-04-12T10:00:00Z",
      environment: "prod",
      projectHost: "example.supabase.co",
      overallLevel: "healthy",
      jobs: [{
        name: "build-feed",
        level: "healthy",
        summary: "succeeded with last success 1.0h ago",
        status: "succeeded",
        lastStartedAt: "2026-04-12T08:00:00Z",
        lastFinishedAt: "2026-04-12T08:05:00Z",
        lastSucceededAt: "2026-04-12T08:05:00Z",
        expiresAt: "2026-04-12T08:05:00Z",
        ageHours: 1,
        lastError: null,
      }],
      tables: [{
        name: "feed_items",
        level: "healthy",
        summary: "latest delivered_at 1.0h ago",
        timestampField: "delivered_at",
        latestAt: "2026-04-12T09:00:00Z",
        ageHours: 1,
        totalCount: 20,
        recentCount: 20,
        recentWindowHours: 24,
      }],
    },
  });

  if (!text.includes("Overall: pass")) {
    throw new Error("expected overall line");
  }
  if (!text.includes("[pass] Supabase URL")) {
    throw new Error("expected env check line");
  }
  if (!text.includes("[pass] feed_items")) {
    throw new Error("expected table line");
  }
  if (!text.includes("Backend health: healthy")) {
    throw new Error("expected backend health line");
  }
});
