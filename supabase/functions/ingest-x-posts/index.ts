import { createClient } from "jsr:@supabase/supabase-js@2";
import { sanitizeExternalContent } from "../_shared/content_safety.ts";
import { resolveCostControls } from "../_shared/cost_controls.ts";
import { corsHeaders } from "../_shared/cors.ts";
import {
  getOptionalScopedEnv,
  getScopedEnvOrDefault,
  resolveSupabaseServiceConfig,
} from "../_shared/environment.ts";
import {
  normalizeAssetUrl,
  normalizeMediaUrls,
  normalizeSourceUrl,
} from "../_shared/media.ts";
import {
  createObservationContext,
  logEdgeEvent,
  logEdgeFailure,
  logEdgeStart,
  logEdgeSuccess,
} from "../_shared/observability.ts";
import {
  createProviderMetricContext,
  logProviderMetricFailure,
  logProviderMetricSuccess,
} from "../_shared/provider_metrics.ts";
import {
  claimPipelineJob,
  completePipelineJob,
} from "../_shared/pipeline_lock.ts";
import {
  defaultUsernames,
  normalizeUsername,
  resolvePersona,
  resolvePersonaById,
} from "../_shared/personas.ts";

type JsonRecord = Record<string, unknown>;

type ActorAttemptSummary = {
  name: string;
  status: string;
  statusMessage: string | null;
  itemCount: number;
};

type ActorRunResult = {
  actorId: string;
  matchedAttempt: string | null;
  summaries: ActorAttemptSummary[];
  posts: JsonRecord[];
  blockedReason: string | null;
};

type ActorExecution = {
  actorId: string;
  matchedAttempt: string | null;
  usernames: string[];
  summaries: ActorAttemptSummary[];
  posts: JsonRecord[];
  blockedReason: string | null;
};

type NormalizedPost = {
  id: string;
  personaId: string;
  content: string;
  sourceType: "x";
  sourceUrl: string | null;
  topic: string | null;
  importanceScore: number;
  mediaUrls: string[];
  videoUrl: string | null;
  publishedAt: string;
  rawAuthorUsername: string;
  rawPayload: JsonRecord;
};

type ContentSafetyStats = {
  blocked: number;
  sanitized: number;
};

type SelfHostedIngestResponse = {
  ok?: unknown;
  provider?: unknown;
  matchedAttempt?: unknown;
  blockedReason?: unknown;
  summaries?: unknown;
  posts?: unknown;
  error?: unknown;
};

function extractString(value: unknown): string | null {
  return typeof value === "string" && value.trim().length > 0
    ? value.trim()
    : null;
}

function extractRecord(value: unknown): JsonRecord | null {
  return value && typeof value === "object"
    ? value as JsonRecord
    : null;
}

function extractRecordArray(value: unknown): JsonRecord[] {
  if (!Array.isArray(value)) return [];
  return value.filter((item) => item && typeof item === "object") as JsonRecord[];
}

function extractStringArray(value: unknown): string[] {
  if (!Array.isArray(value)) return [];
  return value.map((item) => extractString(item)).filter((item): item is string =>
    item !== null
  );
}

function extractAttemptSummaries(value: unknown): ActorAttemptSummary[] {
  if (!Array.isArray(value)) return [];

  return value.map((item) => {
    const record = extractRecord(item);
    if (!record) return null;

    const name = extractString(record.name);
    const status = extractString(record.status);
    if (!name || !status) return null;

    const itemCountValue = typeof record.itemCount === "number"
      ? record.itemCount
      : Number.parseInt(String(record.itemCount ?? "0"), 10);

    return {
      name,
      status,
      statusMessage: extractString(record.statusMessage),
      itemCount: Number.isFinite(itemCountValue) ? itemCountValue : 0,
    } satisfies ActorAttemptSummary;
  }).filter((item): item is ActorAttemptSummary => item !== null);
}

function resolveXIngestProvider(): "self_hosted_service" {
  const raw = getOptionalScopedEnv("BRUH_X_INGEST_PROVIDER")
    ?.trim()
    .toLowerCase() ?? "self_hosted_service";

  switch (raw) {
    case "":
    case "self_hosted":
    case "self-hosted":
    case "self_hosted_service":
    case "self-hosted-service":
    case "selfhosted":
      return "self_hosted_service";
    case "apify":
      throw new Error(
        "Apify X ingest provider has been removed. Use self_hosted_service.",
      );
    default:
      throw new Error(
        `Unsupported BRUH_X_INGEST_PROVIDER '${raw}'. Expected 'self_hosted_service'.`,
      );
  }
}

function limitPostsPerUser(
  posts: NormalizedPost[],
  limitPerUser: number,
): NormalizedPost[] {
  const counts = new Map<string, number>();

  return posts
    .sort((left, right) =>
      new Date(right.publishedAt).getTime() -
      new Date(left.publishedAt).getTime()
    )
    .filter((post) => {
      const current = counts.get(post.rawAuthorUsername) ?? 0;
      if (current >= limitPerUser) {
        return false;
      }

      counts.set(post.rawAuthorUsername, current + 1);
      return true;
    });
}

function coercePreNormalizedPost(raw: unknown): NormalizedPost | null {
  const record = extractRecord(raw);
  if (!record) return null;

  const id = extractString(record.id);
  const content = extractString(record.content);
  const rawAuthorUsername = extractString(
    record.rawAuthorUsername ?? record.raw_author_username,
  );
  const personaId = extractString(record.personaId ?? record.persona_id);

  if (!id || !content || !rawAuthorUsername) {
    return null;
  }

  const persona = resolvePersonaById(personaId ?? "") ??
    resolvePersona(rawAuthorUsername);
  if (!persona) {
    return null;
  }

  const publishedAtValue = extractString(
    record.publishedAt ?? record.published_at,
  );
  if (!publishedAtValue) {
    return null;
  }

  const publishedAt = new Date(publishedAtValue);
  if (Number.isNaN(publishedAt.getTime())) {
    return null;
  }

  const importanceScoreValue = typeof (record.importanceScore ??
      record.importance_score) === "number"
    ? record.importanceScore ?? record.importance_score
    : Number.parseFloat(String(record.importanceScore ??
      record.importance_score ?? "0.5"));

  const mediaUrls = normalizeMediaUrls(
    extractStringArray(record.mediaUrls ?? record.media_urls),
  );
  const videoUrl = normalizeAssetUrl(
    extractString(record.videoUrl ?? record.video_url),
  );
  const sourceUrl = normalizeSourceUrl(
    extractString(record.sourceUrl ?? record.source_url),
  );
  const rawPayload = extractRecord(record.rawPayload ?? record.raw_payload) ??
    {
      serviceNormalized: true,
      sourceUrl,
      mediaUrls,
      videoUrl,
    } satisfies JsonRecord;

  return {
    id,
    personaId: persona.personaId,
    content,
    sourceType: "x",
    sourceUrl,
    topic: extractString(record.topic),
    importanceScore: Number.isFinite(importanceScoreValue)
      ? Number(importanceScoreValue)
      : 0.5,
    mediaUrls,
    videoUrl,
    publishedAt: publishedAt.toISOString(),
    rawAuthorUsername: normalizeUsername(rawAuthorUsername),
    rawPayload,
  };
}

function normalizePreNormalizedPost(
  raw: unknown,
  contentSafety: ContentSafetyStats,
): NormalizedPost | null {
  const coerced = coercePreNormalizedPost(raw);
  if (!coerced) {
    return null;
  }

  const contentSafetyResult = sanitizeExternalContent(coerced.content, {
    maxLength: 320,
  });
  if (contentSafetyResult.blocked || !contentSafetyResult.text) {
    contentSafety.blocked += 1;
    return null;
  }
  if (contentSafetyResult.sanitized) {
    contentSafety.sanitized += 1;
  }

  return {
    ...coerced,
    content: contentSafetyResult.text,
  };
}

async function runSelfHostedService(
  usernames: string[],
  limitPerUser: number,
): Promise<ActorRunResult> {
  const configuredUrl = getOptionalScopedEnv(
    "BRUH_X_SELF_HOSTED_SERVICE_URL",
    {
      aliases: [
        "X_INGEST_SERVICE_URL",
        "BRUH_X_SCRAPER_SERVICE_URL",
      ],
    },
  );
  if (!configuredUrl) {
    throw new Error(
      "Missing BRUH_X_SELF_HOSTED_SERVICE_URL for self-hosted X ingestion.",
    );
  }

  const token = getOptionalScopedEnv(
    "BRUH_X_SELF_HOSTED_SERVICE_TOKEN",
    {
      aliases: [
        "X_INGEST_SERVICE_TOKEN",
        "BRUH_X_SCRAPER_SERVICE_TOKEN",
      ],
    },
  );
  const timeoutMsRaw = Number.parseInt(
    getScopedEnvOrDefault(
      "BRUH_X_SELF_HOSTED_SERVICE_TIMEOUT_MS",
      "120000",
      {
        aliases: [
          "X_INGEST_SERVICE_TIMEOUT_MS",
        ],
      },
    ),
    10,
  );
  const timeoutMs = Number.isFinite(timeoutMsRaw) && timeoutMsRaw > 0
    ? timeoutMsRaw
    : 120000;

  const url = new URL(configuredUrl);
  if (url.pathname === "/" || url.pathname === "") {
    url.pathname = "/fetch";
  }

  const metric = createProviderMetricContext(
    "ingest-x-posts",
    "x_ingest_actor",
    "self_hosted:service",
    {
      baseUrl: url.origin,
    },
  );

  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), timeoutMs);

  try {
    const response = await fetch(url, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        ...(token ? { Authorization: `Bearer ${token}` } : {}),
      },
      body: JSON.stringify({
        usernames,
        limitPerUser,
      }),
      signal: controller.signal,
    });

    const responseText = await response.text();
    let payload: SelfHostedIngestResponse | null = null;
    try {
      payload = responseText
        ? JSON.parse(responseText) as SelfHostedIngestResponse
        : null;
    } catch {
      payload = null;
    }

    if (!response.ok) {
      const message = extractString(payload?.error) ??
        extractString(payload?.blockedReason) ??
        (responseText ||
          `Self-hosted X ingest service returned ${response.status}`);
      logProviderMetricFailure(metric, message, {
        status: "HTTP_ERROR",
        httpStatus: response.status,
      });
      return {
        actorId: "self_hosted:service",
        matchedAttempt: null,
        summaries: [{
          name: "self_hosted_service",
          status: "HTTP_ERROR",
          statusMessage: message,
          itemCount: 0,
        }],
        posts: [],
        blockedReason: message,
      };
    }

    const posts = extractRecordArray(payload?.posts);
    const summaries = extractAttemptSummaries(payload?.summaries);
    const blockedReason = extractString(payload?.blockedReason);
    const providerId = extractString(payload?.provider) ??
      "self_hosted:service";
    const matchedAttempt = extractString(payload?.matchedAttempt);
    const itemCount = posts.length;

    logProviderMetricSuccess(metric, {
      providerId,
      matchedAttempt,
      itemCount,
    });

    return {
      actorId: providerId,
      matchedAttempt,
      summaries: summaries.length > 0
        ? summaries
        : [{
          name: "self_hosted_service",
          status: blockedReason ? "PARTIAL" : "SUCCEEDED",
          statusMessage: blockedReason,
          itemCount,
        }],
      posts,
      blockedReason,
    };
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    logProviderMetricFailure(metric, message, {
      status: "REQUEST_FAILED",
    });
    return {
      actorId: "self_hosted:service",
      matchedAttempt: null,
      summaries: [{
        name: "self_hosted_service",
        status: "REQUEST_FAILED",
        statusMessage: message,
        itemCount: 0,
      }],
      posts: [],
      blockedReason: message,
    };
  } finally {
    clearTimeout(timeout);
  }
}

const port = Number(Deno.env.get("PORT") ?? "8000");

Deno.serve({ port }, async (request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  const observation = createObservationContext("ingest-x-posts");
  logEdgeStart(observation, "job_started", {
    method: request.method,
  });

  try {
    const { projectUrl, serviceRoleKey } = resolveSupabaseServiceConfig();
    const costControls = resolveCostControls();
    const xIngestProvider = resolveXIngestProvider();

    if (costControls.xIngestMode !== "enabled") {
      logEdgeSuccess(observation, "job_skipped", {
        reason: "cost_controlled_disabled",
        xIngestMode: costControls.xIngestMode,
      });
      return Response.json(
        {
          ok: true,
          skipped: true,
          reason: "cost_controlled_disabled",
          xIngestMode: costControls.xIngestMode,
        },
        { headers: corsHeaders },
      );
    }

    const supabase = createClient(projectUrl, serviceRoleKey);
    const lock = await claimPipelineJob(supabase, "ingest-x-posts", 25 * 60);
    if (!lock.acquired) {
      logEdgeSuccess(observation, "job_skipped", {
        reason: "already_running",
        lockedBy: lock.currentOwnerId,
        lockedUntil: lock.expiresAt,
      });
      return Response.json(
        {
          ok: true,
          skipped: true,
          reason: "already_running",
          lockedBy: lock.currentOwnerId,
          lockedUntil: lock.expiresAt,
        },
        { headers: corsHeaders },
      );
    }

    try {
      const body = request.method === "POST"
        ? await request.json().catch(() => ({}))
        : {};
      const requestedUsernames: string[] = Array.isArray(body.usernames)
        ? body.usernames.map((value: unknown) =>
          normalizeUsername(String(value))
        ).filter((value: string) => resolvePersona(value))
        : defaultUsernames;
      const usernames: string[] = [...new Set(requestedUsernames)].slice(
        0,
        costControls.maxXUsernamesPerRun,
      );
      const limitPerUserRaw = Number.parseInt(
        String(body.limitPerUser ?? 5),
        10,
      );
      const limitPerUser = Number.isNaN(limitPerUserRaw)
        ? Math.min(5, costControls.maxXPostsPerUser)
        : Math.min(Math.max(limitPerUserRaw, 1), costControls.maxXPostsPerUser);
      const debugSample = body.debugSample === true;
      const contentSafety = { blocked: 0, sanitized: 0 };

      if (usernames.length === 0) {
        await completePipelineJob(
          supabase,
          "ingest-x-posts",
          lock.ownerId,
          true,
        );
        logEdgeSuccess(observation, "job_skipped", {
          reason: "no_supported_usernames",
        });
        return Response.json(
          {
            ok: true,
            skipped: true,
            reason: "no_supported_usernames",
          },
          { headers: corsHeaders },
        );
      }

      const executions: ActorExecution[] = [];
      const result = await runSelfHostedService(usernames, limitPerUser);
      executions.push({
        actorId: result.actorId,
        matchedAttempt: result.matchedAttempt,
        usernames,
        summaries: result.summaries,
        posts: result.posts,
        blockedReason: result.blockedReason,
      });

      const serviceNormalizedPosts = executions.flatMap((execution) =>
        execution.posts
      );
      const totalFetched = serviceNormalizedPosts.length;
      const blockedReasons = executions
        .filter((execution) => execution.blockedReason)
        .map((execution) => ({
          actorId: execution.actorId,
          usernames: execution.usernames,
          reason: execution.blockedReason,
        }));

      if (debugSample) {
        await completePipelineJob(
          supabase,
          "ingest-x-posts",
          lock.ownerId,
          true,
        );
        logEdgeSuccess(observation, "job_succeeded", {
          debugSample: true,
          actorCount: executions.length,
          totalFetched,
        });
        return Response.json(
          {
            ok: true,
            actors: executions.map((execution) => ({
              actorId: execution.actorId,
              usernames: execution.usernames,
              matchedAttempt: execution.matchedAttempt,
              attempts: execution.summaries,
              blockedReason: execution.blockedReason,
            })),
            blockedReason: blockedReasons.length > 0 ? blockedReasons : null,
            usernames,
            totalFetched,
            maxUsernamesPerRun: costControls.maxXUsernamesPerRun,
            maxPostsPerUser: costControls.maxXPostsPerUser,
            sample: serviceNormalizedPosts.slice(0, 3),
          },
          { headers: corsHeaders },
        );
      }

      if (
        blockedReasons.length === executions.length && blockedReasons.length > 0
      ) {
        await completePipelineJob(
          supabase,
          "ingest-x-posts",
          lock.ownerId,
          false,
          JSON.stringify(blockedReasons),
        );
        logEdgeFailure(
          observation,
          "job_failed",
          JSON.stringify(blockedReasons),
          {
            actorCount: executions.length,
            usernames,
          },
        );
        return Response.json(
          {
            ok: false,
            actorId: executions.length === 1
              ? executions[0].actorId
              : "multiple",
            matchedAttempt: executions.length === 1
              ? executions[0].matchedAttempt
              : null,
            blockedReason: blockedReasons,
            usernames,
            totalFetched: 0,
            normalized: 0,
            inserted: 0,
            updated: 0,
            skipped: 0,
          },
          { headers: corsHeaders },
        );
      }

      const posts = limitPostsPerUser(
        serviceNormalizedPosts
          .map((post) => normalizePreNormalizedPost(post, contentSafety))
          .filter((post): post is NormalizedPost => post !== null),
        limitPerUser,
      );

      if (contentSafety.blocked > 0 || contentSafety.sanitized > 0) {
        logEdgeEvent("ingest-x-posts", "content_safety_applied", {
          blocked: contentSafety.blocked,
          sanitized: contentSafety.sanitized,
          fetchedItems: totalFetched,
        });
      }

      const existingIds = posts.map((post) => post.id);

      let existingIdSet = new Set<string>();
      if (existingIds.length > 0) {
        const { data: existingRows, error: existingError } = await supabase
          .from("source_posts")
          .select("id")
          .in("id", existingIds);

        if (existingError) {
          throw new Error(existingError.message);
        }

        existingIdSet = new Set(
          (existingRows ?? []).map((row) => row.id as string),
        );
      }

      if (posts.length > 0) {
        const { error } = await supabase
          .from("source_posts")
          .upsert(
            posts.map((post) => ({
              id: post.id,
              persona_id: post.personaId,
              source_type: post.sourceType,
              content: post.content,
              source_url: post.sourceUrl,
              topic: post.topic,
              importance_score: post.importanceScore,
              media_urls: post.mediaUrls,
              video_url: post.videoUrl,
              published_at: post.publishedAt,
              raw_author_username: post.rawAuthorUsername,
              raw_payload: post.rawPayload,
            })),
            { onConflict: "id" },
          );

        if (error) {
          throw new Error(error.message);
        }
      }

      const inserted = posts.filter((post) =>
        !existingIdSet.has(post.id)
      ).length;
      const updated = posts.length - inserted;
      const skipped = totalFetched - posts.length;

      await completePipelineJob(supabase, "ingest-x-posts", lock.ownerId, true);
      logEdgeSuccess(observation, "job_succeeded", {
        actorCount: executions.length,
        provider: xIngestProvider,
        totalFetched,
        normalized: posts.length,
        inserted,
        updated,
        skipped,
      });
      return Response.json(
        {
          ok: true,
          actorId: executions.length === 1 ? executions[0].actorId : "multiple",
          matchedAttempt: executions.length === 1
            ? executions[0].matchedAttempt
            : null,
          actorsUsed: executions.map((execution) => ({
            actorId: execution.actorId,
            usernames: execution.usernames,
            matchedAttempt: execution.matchedAttempt,
          })),
          usernames,
          provider: xIngestProvider,
          totalFetched,
          normalized: posts.length,
          inserted,
          updated,
          skipped,
          maxUsernamesPerRun: costControls.maxXUsernamesPerRun,
          maxPostsPerUser: costControls.maxXPostsPerUser,
        },
        { headers: corsHeaders },
      );
    } catch (error) {
      await completePipelineJob(
        supabase,
        "ingest-x-posts",
        lock.ownerId,
        false,
        error instanceof Error ? error.message : String(error),
      );
      logEdgeFailure(observation, "job_failed", error, {
        ownerId: lock.ownerId,
      });
      throw error;
    }
  } catch (error) {
    logEdgeFailure(observation, "request_failed", error);
    return Response.json(
      { error: error instanceof Error ? error.message : "Unknown error" },
      { status: 500, headers: corsHeaders },
    );
  }
});
