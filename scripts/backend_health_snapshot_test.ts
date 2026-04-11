import {
  formatHealthSnapshot,
  overallHealthLevel,
  summarizeJobHealth,
  summarizeTableHealth,
} from "./backend_health_snapshot_lib.ts";

Deno.test("summarizeJobHealth marks recent success as healthy", () => {
  const snapshot = summarizeJobHealth(
    {
      name: "build-feed",
      degradedAfterHours: 6,
      staleAfterHours: 12,
    },
    {
      job_name: "build-feed",
      status: "succeeded",
      locked_at: "2026-04-12T00:00:00Z",
      expires_at: "2026-04-12T00:00:00Z",
      last_started_at: "2026-04-12T00:00:00Z",
      last_finished_at: "2026-04-12T00:05:00Z",
      last_succeeded_at: "2026-04-12T08:00:00Z",
      last_error: null,
    },
    new Date("2026-04-12T10:00:00Z"),
  );

  if (snapshot.level != "healthy") {
    throw new Error(`expected healthy, got ${snapshot.level}`);
  }
});

Deno.test("summarizeJobHealth marks failed jobs as failed", () => {
  const snapshot = summarizeJobHealth(
    {
      name: "ingest-x-posts",
      degradedAfterHours: 6,
      staleAfterHours: 12,
    },
    {
      job_name: "ingest-x-posts",
      status: "failed",
      locked_at: "2026-04-12T00:00:00Z",
      expires_at: "2026-04-12T00:00:00Z",
      last_started_at: "2026-04-12T00:00:00Z",
      last_finished_at: "2026-04-12T00:05:00Z",
      last_succeeded_at: "2026-04-11T00:00:00Z",
      last_error: "quota exceeded",
    },
    new Date("2026-04-12T10:00:00Z"),
  );

  if (snapshot.level != "failed") {
    throw new Error(`expected failed, got ${snapshot.level}`);
  }
});

Deno.test("summarizeTableHealth marks stale tables", () => {
  const snapshot = summarizeTableHealth(
    {
      name: "news_articles",
      timestampField: "fetched_at",
      recentWindowHours: 24,
      degradedAfterHours: 6,
      staleAfterHours: 12,
    },
    {
      totalCount: 42,
      latestAt: "2026-04-11T00:00:00Z",
      recentCount: 0,
    },
    new Date("2026-04-12T10:00:00Z"),
  );

  if (snapshot.level != "stale") {
    throw new Error(`expected stale, got ${snapshot.level}`);
  }
});

Deno.test("overallHealthLevel reflects the worst component", () => {
  const level = overallHealthLevel({
    jobs: [{ level: "healthy" }, { level: "failed" }],
    tables: [{ level: "degraded" }],
  });

  if (level != "failed") {
    throw new Error(`expected failed overall, got ${level}`);
  }
});

Deno.test("formatHealthSnapshot renders jobs and tables", () => {
  const text = formatHealthSnapshot({
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
  });

  if (!text.includes("Overall: healthy")) {
    throw new Error("expected overall line");
  }
  if (!text.includes("[healthy] build-feed")) {
    throw new Error("expected job line");
  }
  if (!text.includes("[healthy] feed_items")) {
    throw new Error("expected table line");
  }
});
