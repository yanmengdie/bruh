import type { SupabaseClient } from "jsr:@supabase/supabase-js@2";

export type HealthLevel =
  | "healthy"
  | "running"
  | "degraded"
  | "stale"
  | "failed"
  | "error"
  | "unknown";

export type JobSnapshot = {
  name: string;
  level: HealthLevel;
  summary: string;
  status: string;
  lastStartedAt: string | null;
  lastFinishedAt: string | null;
  lastSucceededAt: string | null;
  expiresAt: string | null;
  ageHours: number | null;
  lastError: string | null;
};

export type TableSnapshot = {
  name: string;
  level: HealthLevel;
  summary: string;
  timestampField: string;
  latestAt: string | null;
  ageHours: number | null;
  totalCount: number | null;
  recentCount: number | null;
  recentWindowHours: number;
};

export type BackendHealthSnapshot = {
  checkedAt: string;
  environment: string;
  projectHost: string;
  overallLevel: HealthLevel;
  jobs: JobSnapshot[];
  tables: TableSnapshot[];
};

type PipelineJobLockRow = {
  job_name: string;
  status: string;
  locked_at: string | null;
  expires_at: string | null;
  last_started_at: string | null;
  last_finished_at: string | null;
  last_succeeded_at: string | null;
  last_error: string | null;
};

type TableHealthConfig = {
  name: string;
  timestampField: string;
  recentWindowHours: number;
  degradedAfterHours: number;
  staleAfterHours: number;
};

type JobHealthConfig = {
  name: string;
  degradedAfterHours: number;
  staleAfterHours: number;
};

type TableProbe = {
  totalCount: number | null;
  latestAt: string | null;
  recentCount: number | null;
};

const expectedJobs: JobHealthConfig[] = [
  { name: "ingest-top-news", degradedAfterHours: 6, staleAfterHours: 12 },
  { name: "build-news-events", degradedAfterHours: 6, staleAfterHours: 12 },
  { name: "ingest-x-posts", degradedAfterHours: 6, staleAfterHours: 12 },
  { name: "build-feed", degradedAfterHours: 6, staleAfterHours: 12 },
];

const expectedTables: TableHealthConfig[] = [
  {
    name: "news_articles",
    timestampField: "fetched_at",
    recentWindowHours: 24,
    degradedAfterHours: 6,
    staleAfterHours: 12,
  },
  {
    name: "news_events",
    timestampField: "updated_at",
    recentWindowHours: 24,
    degradedAfterHours: 6,
    staleAfterHours: 12,
  },
  {
    name: "persona_news_scores",
    timestampField: "updated_at",
    recentWindowHours: 24,
    degradedAfterHours: 6,
    staleAfterHours: 12,
  },
  {
    name: "feed_items",
    timestampField: "delivered_at",
    recentWindowHours: 24,
    degradedAfterHours: 6,
    staleAfterHours: 12,
  },
  {
    name: "source_posts",
    timestampField: "published_at",
    recentWindowHours: 72,
    degradedAfterHours: 48,
    staleAfterHours: 96,
  },
];

const healthSeverity: Record<HealthLevel, number> = {
  healthy: 0,
  running: 0,
  degraded: 1,
  stale: 2,
  failed: 3,
  error: 4,
  unknown: 5,
};

function roundHours(value: number) {
  return Math.round(value * 10) / 10;
}

export function hoursSince(
  timestamp: string | null,
  now = new Date(),
): number | null {
  if (!timestamp) return null;
  const parsed = Date.parse(timestamp);
  if (Number.isNaN(parsed)) return null;
  return roundHours((now.getTime() - parsed) / (1000 * 60 * 60));
}

export function formatAgeHours(ageHours: number | null): string {
  if (ageHours === null) return "never";
  if (ageHours < 1) {
    const minutes = Math.max(1, Math.round(ageHours * 60));
    return `${minutes}m ago`;
  }
  return `${ageHours.toFixed(1)}h ago`;
}

function latestLevel(levels: HealthLevel[]) {
  return levels.reduce<HealthLevel>(
    (current, candidate) =>
      healthSeverity[candidate] > healthSeverity[current] ? candidate : current,
    "healthy",
  );
}

export function summarizeJobHealth(
  config: JobHealthConfig,
  row: PipelineJobLockRow | null,
  now = new Date(),
): JobSnapshot {
  if (!row) {
    return {
      name: config.name,
      level: "unknown",
      summary: "no lock row yet",
      status: "missing",
      lastStartedAt: null,
      lastFinishedAt: null,
      lastSucceededAt: null,
      expiresAt: null,
      ageHours: null,
      lastError: null,
    };
  }

  const ageHours = hoursSince(row.last_succeeded_at, now);
  const expiresAt = row.expires_at;
  const expiresMs = expiresAt ? Date.parse(expiresAt) : NaN;
  const isExpired = Number.isFinite(expiresMs) && expiresMs <= now.getTime();

  if (row.status === "running" && !isExpired) {
    return {
      name: config.name,
      level: "running",
      summary: `running, lock expires ${
        formatAgeHours(hoursSince(expiresAt, now)) === "never"
          ? "unknown"
          : expiresAt
      }`,
      status: row.status,
      lastStartedAt: row.last_started_at,
      lastFinishedAt: row.last_finished_at,
      lastSucceededAt: row.last_succeeded_at,
      expiresAt,
      ageHours,
      lastError: row.last_error,
    };
  }

  if (row.status === "failed") {
    return {
      name: config.name,
      level: "failed",
      summary: row.last_error ? `failed: ${row.last_error}` : "failed",
      status: row.status,
      lastStartedAt: row.last_started_at,
      lastFinishedAt: row.last_finished_at,
      lastSucceededAt: row.last_succeeded_at,
      expiresAt,
      ageHours,
      lastError: row.last_error,
    };
  }

  if (ageHours === null) {
    return {
      name: config.name,
      level: "unknown",
      summary: "no successful run yet",
      status: row.status,
      lastStartedAt: row.last_started_at,
      lastFinishedAt: row.last_finished_at,
      lastSucceededAt: row.last_succeeded_at,
      expiresAt,
      ageHours,
      lastError: row.last_error,
    };
  }

  const level: HealthLevel = ageHours > config.staleAfterHours
    ? "stale"
    : ageHours > config.degradedAfterHours
    ? "degraded"
    : "healthy";

  return {
    name: config.name,
    level,
    summary: `${row.status} with last success ${formatAgeHours(ageHours)}`,
    status: row.status,
    lastStartedAt: row.last_started_at,
    lastFinishedAt: row.last_finished_at,
    lastSucceededAt: row.last_succeeded_at,
    expiresAt,
    ageHours,
    lastError: row.last_error,
  };
}

export function summarizeTableHealth(
  config: TableHealthConfig,
  probe: TableProbe | null,
  now = new Date(),
): TableSnapshot {
  if (!probe || probe.totalCount === null) {
    return {
      name: config.name,
      level: "error",
      summary: "table probe failed",
      timestampField: config.timestampField,
      latestAt: null,
      ageHours: null,
      totalCount: null,
      recentCount: null,
      recentWindowHours: config.recentWindowHours,
    };
  }

  if (probe.totalCount === 0 || !probe.latestAt) {
    return {
      name: config.name,
      level: "unknown",
      summary: "no rows yet",
      timestampField: config.timestampField,
      latestAt: probe.latestAt,
      ageHours: null,
      totalCount: probe.totalCount,
      recentCount: probe.recentCount,
      recentWindowHours: config.recentWindowHours,
    };
  }

  const ageHours = hoursSince(probe.latestAt, now);
  const level: HealthLevel = ageHours === null
    ? "error"
    : ageHours > config.staleAfterHours
    ? "stale"
    : ageHours > config.degradedAfterHours
    ? "degraded"
    : "healthy";

  return {
    name: config.name,
    level,
    summary: `latest ${config.timestampField} ${formatAgeHours(ageHours)}`,
    timestampField: config.timestampField,
    latestAt: probe.latestAt,
    ageHours,
    totalCount: probe.totalCount,
    recentCount: probe.recentCount,
    recentWindowHours: config.recentWindowHours,
  };
}

export function overallHealthLevel(snapshot: {
  jobs: Array<{ level: HealthLevel }>;
  tables: Array<{ level: HealthLevel }>;
}): HealthLevel {
  return latestLevel([
    ...snapshot.jobs.map((item) => item.level),
    ...snapshot.tables.map((item) => item.level),
  ]);
}

async function fetchLatestTimestamp(
  supabase: SupabaseClient,
  table: string,
  field: string,
): Promise<string | null> {
  const { data, error } = await supabase
    .from(table)
    .select(field)
    .not(field, "is", null)
    .order(field, { ascending: false, nullsFirst: false })
    .limit(1);

  if (error) {
    throw new Error(`Failed to query ${table}.${field}: ${error.message}`);
  }

  const firstRow = Array.isArray(data) && data.length > 0 &&
      typeof data[0] === "object" && data[0] !== null
    ? data[0] as Record<string, unknown>
    : null;
  const value = firstRow?.[field];
  return typeof value === "string" ? value : null;
}

async function fetchCount(
  supabase: SupabaseClient,
  table: string,
  field?: string,
  recentWindowHours?: number,
  now = new Date(),
): Promise<number | null> {
  let query = supabase.from(table).select("*", { count: "exact", head: true });
  if (field && recentWindowHours !== undefined) {
    const sinceIso = new Date(
      now.getTime() - recentWindowHours * 60 * 60 * 1000,
    ).toISOString();
    query = query.gte(field, sinceIso);
  }

  const { count, error } = await query;
  if (error) {
    throw new Error(`Failed to count ${table}: ${error.message}`);
  }

  return count ?? 0;
}

async function probeTable(
  supabase: SupabaseClient,
  config: TableHealthConfig,
  now = new Date(),
): Promise<TableProbe | null> {
  try {
    const [totalCount, latestAt, recentCount] = await Promise.all([
      fetchCount(supabase, config.name),
      fetchLatestTimestamp(supabase, config.name, config.timestampField),
      fetchCount(
        supabase,
        config.name,
        config.timestampField,
        config.recentWindowHours,
        now,
      ),
    ]);

    return { totalCount, latestAt, recentCount };
  } catch {
    return null;
  }
}

async function fetchPipelineJobRows(
  supabase: SupabaseClient,
): Promise<Map<string, PipelineJobLockRow>> {
  const { data, error } = await supabase
    .from("pipeline_job_locks")
    .select(
      "job_name, status, locked_at, expires_at, last_started_at, last_finished_at, last_succeeded_at, last_error",
    )
    .order("job_name", { ascending: true });

  if (error) {
    throw new Error(`Failed to query pipeline_job_locks: ${error.message}`);
  }

  return new Map(
    ((data ?? []) as PipelineJobLockRow[]).map((row) => [row.job_name, row]),
  );
}

function projectHost(projectUrl: string) {
  try {
    return new URL(projectUrl).host;
  } catch {
    return projectUrl;
  }
}

export async function collectBackendHealthSnapshot(
  supabase: SupabaseClient,
  options: {
    environment: string;
    projectUrl: string;
    now?: Date;
  },
): Promise<BackendHealthSnapshot> {
  const now = options.now ?? new Date();
  const checkedAt = now.toISOString();

  let jobRows = new Map<string, PipelineJobLockRow>();
  try {
    jobRows = await fetchPipelineJobRows(supabase);
  } catch {
    jobRows = new Map<string, PipelineJobLockRow>();
  }

  const jobs = expectedJobs.map((config) =>
    summarizeJobHealth(config, jobRows.get(config.name) ?? null, now)
  );

  const tableProbes = await Promise.all(
    expectedTables.map(async (config) => ({
      config,
      probe: await probeTable(supabase, config, now),
    })),
  );

  const tables = tableProbes.map(({ config, probe }) =>
    summarizeTableHealth(config, probe, now)
  );

  return {
    checkedAt,
    environment: options.environment,
    projectHost: projectHost(options.projectUrl),
    overallLevel: overallHealthLevel({ jobs, tables }),
    jobs,
    tables,
  };
}

export function formatHealthSnapshot(snapshot: BackendHealthSnapshot): string {
  const lines = [
    `Environment: ${snapshot.environment}`,
    `Project: ${snapshot.projectHost}`,
    `Checked at: ${snapshot.checkedAt}`,
    `Overall: ${snapshot.overallLevel}`,
    "",
    "Jobs:",
    ...snapshot.jobs.map((job) => {
      const suffix = job.lastSucceededAt
        ? `, last success ${formatAgeHours(job.ageHours)}`
        : "";
      return `- [${job.level}] ${job.name}: ${job.summary}${suffix}`;
    }),
    "",
    "Tables:",
    ...snapshot.tables.map((table) => {
      const counts = table.totalCount === null
        ? ""
        : `, total=${table.totalCount}, recent${table.recentWindowHours}h=${
          table.recentCount ?? 0
        }`;
      return `- [${table.level}] ${table.name}: ${table.summary}${counts}`;
    }),
  ];

  return lines.join("\n");
}
