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
  logProviderMetricFallback,
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
} from "../_shared/personas.ts";

type ApifyItem = Record<string, unknown>;

type ActorAttempt = {
  name: string;
  input: Record<string, unknown>;
};

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
  items: ApifyItem[];
  blockedReason: string | null;
};

type ActorExecution = {
  actorId: string;
  matchedAttempt: string | null;
  usernames: string[];
  summaries: ActorAttemptSummary[];
  items: ApifyItem[];
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
  rawPayload: ApifyItem;
};

type ContentSafetyStats = {
  blocked: number;
  sanitized: number;
};

function extractString(value: unknown): string | null {
  return typeof value === "string" && value.trim().length > 0
    ? value.trim()
    : null;
}

function extractRecord(value: unknown): Record<string, unknown> | null {
  return value && typeof value === "object"
    ? value as Record<string, unknown>
    : null;
}

function extractItemArray(value: unknown): ApifyItem[] {
  if (!Array.isArray(value)) return [];
  return value.filter((item) =>
    item && typeof item === "object"
  ) as ApifyItem[];
}

function extractAuthorUsername(item: ApifyItem): string | null {
  const candidates = [
    item.authorUsername,
    item.userName,
    item.username,
    item.screenName,
    item.screen_name,
    (item.author as Record<string, unknown> | undefined)?.screenName,
    (item.author as Record<string, unknown> | undefined)?.screen_name,
    (item.author as Record<string, unknown> | undefined)?.userName,
    (item.author as Record<string, unknown> | undefined)?.username,
    (item.author as Record<string, unknown> | undefined)?.screenName,
    (item.author as Record<string, unknown> | undefined)?.screen_name,
    (item.user as Record<string, unknown> | undefined)?.screen_name,
    (item.user as Record<string, unknown> | undefined)?.username,
    (item.user as Record<string, unknown> | undefined)?.userName,
  ];

  for (const candidate of candidates) {
    const username = extractString(candidate);
    if (username) {
      return normalizeUsername(username);
    }
  }

  return null;
}

function extractPostId(
  item: ApifyItem,
  sourceUrl: string | null,
): string | null {
  const candidates = [
    item.id_str,
    item.id,
    item.tweetId,
    item.postId,
    item.conversationId,
    item.restId,
  ];
  for (const candidate of candidates) {
    const value = extractString(candidate);
    if (value) {
      return value;
    }
  }

  if (sourceUrl) {
    const match = sourceUrl.match(/status\/(\d+)/);
    if (match?.[1]) {
      return match[1];
    }
  }

  return null;
}

function extractContent(item: ApifyItem): string | null {
  const candidates = [
    item.fullText,
    item.full_text,
    item.postText,
    item.text,
    item.description,
  ];
  for (const candidate of candidates) {
    const value = extractString(candidate);
    if (value) {
      return value;
    }
  }
  return null;
}

function extractSourceUrl(
  item: ApifyItem,
  username: string | null,
  postId: string | null,
): string | null {
  const directUrl = extractString(item.postUrl) ?? extractString(item.url) ??
    extractString(item.twitterUrl);
  if (directUrl) {
    return directUrl;
  }

  const permalink = extractString(item.permalink);
  if (permalink && username) {
    return permalink.startsWith("http")
      ? permalink
      : `https://x.com${permalink}`;
  }

  if (username && postId) {
    return `https://x.com/${username}/status/${postId}`;
  }
  return null;
}

function extractPublishedAt(item: ApifyItem): string | null {
  const candidates = [
    item.createdAt,
    item.created_at,
    item.timestamp,
    item.publishedAt,
    item.published_at,
  ];
  for (const candidate of candidates) {
    if (typeof candidate === "number" && Number.isFinite(candidate)) {
      const date = new Date(candidate);
      if (!Number.isNaN(date.getTime())) {
        return date.toISOString();
      }
      continue;
    }

    const value = extractString(candidate);
    if (!value) continue;

    if (/^\d{10,13}$/.test(value)) {
      const numericTimestamp = Number.parseInt(value, 10);
      if (Number.isFinite(numericTimestamp)) {
        const date = new Date(numericTimestamp);
        if (!Number.isNaN(date.getTime())) {
          return date.toISOString();
        }
      }
    }

    const date = new Date(value);
    if (!Number.isNaN(date.getTime())) {
      return date.toISOString();
    }
  }
  return null;
}

function extractMediaEntries(item: ApifyItem): ApifyItem[] {
  const extendedEntities = extractRecord(item.extended_entities);
  const entities = extractRecord(item.entities);

  return [
    ...extractItemArray(extendedEntities?.media),
    ...extractItemArray(entities?.media),
    ...extractItemArray(item.media),
    ...extractItemArray(item.photos),
  ];
}

function extractMediaUrls(item: ApifyItem): string[] {
  const urls = new Set<string>();

  for (const media of extractMediaEntries(item)) {
    const candidates = [
      media.media_url_https,
      media.media_url,
      media.imageUrl,
      media.image_url,
      media.thumbnailUrl,
      media.thumbnail_url,
      media.url,
    ];

    for (const candidate of candidates) {
      const value = extractString(candidate);
      if (!value) continue;
      if (value.includes("t.co/")) continue;
      if (value.includes("/status/")) continue;
      urls.add(value);
      break;
    }
  }

  return [...urls];
}

function extractVideoUrl(item: ApifyItem): string | null {
  const directVideoUrl = extractString(item.videoUrl) ??
    extractString(item.video_url);
  if (directVideoUrl) {
    return directVideoUrl;
  }

  let bestVariant: { url: string; bitrate: number } | null = null;

  for (const media of extractMediaEntries(item)) {
    const videoInfo = extractRecord(media.video_info) ??
      extractRecord(media.videoInfo);
    const variants = extractItemArray(videoInfo?.variants);

    for (const variant of variants) {
      const url = extractString(variant.url);
      if (!url || !url.includes(".mp4")) continue;

      const bitrateValue = typeof variant.bitrate === "number"
        ? variant.bitrate
        : Number.parseInt(String(variant.bitrate ?? "0"), 10);
      const bitrate = Number.isFinite(bitrateValue) ? bitrateValue : 0;

      if (!bestVariant || bitrate > bestVariant.bitrate) {
        bestVariant = { url, bitrate };
      }
    }
  }

  return bestVariant?.url ?? null;
}

function hasVisualMedia(item: ApifyItem): boolean {
  return extractMediaUrls(item).length > 0 || extractVideoUrl(item) !== null;
}

function extractMetricNumber(value: unknown): number {
  if (typeof value === "number" && Number.isFinite(value)) {
    return value;
  }

  if (typeof value === "string") {
    const parsed = Number.parseFloat(value.replace(/,/g, ""));
    return Number.isFinite(parsed) ? parsed : 0;
  }

  return 0;
}

function normalizeContentForQualityCheck(content: string): string {
  return content
    .replace(/https?:\/\/\S+/g, " ")
    .replace(/@\w+/g, " ")
    .replace(/[#*_`~]/g, " ")
    .replace(/\s+/g, " ")
    .trim();
}

function isRetweet(item: ApifyItem, content: string): boolean {
  if (item.is_retweet === true || item.isRetweet === true) {
    return true;
  }

  if ((item.retweeted_status as Record<string, unknown> | undefined) != null) {
    return true;
  }

  return /^RT\s+@/i.test(content);
}

function isLowQualityContent(item: ApifyItem, content: string): boolean {
  if (isRetweet(item, content)) {
    return true;
  }

  const normalized = normalizeContentForQualityCheck(content);
  const visualMedia = hasVisualMedia(item);

  if (normalized.length === 0 && !visualMedia) {
    return true;
  }

  if (normalized.length < 12 && !visualMedia) {
    return true;
  }

  if (/^https?:\/\/\S+$/i.test(content.trim()) && !visualMedia) {
    return true;
  }

  return false;
}

function computeImportanceScore(item: ApifyItem): number {
  const likes = extractMetricNumber(item.likeCount) ||
    extractMetricNumber(item.favorite_count) ||
    extractMetricNumber(item.favoriteCount) ||
    extractMetricNumber(item.favouriteCount);
  const retweets = extractMetricNumber(item.retweetCount) ||
    extractMetricNumber(item.retweet_count) ||
    extractMetricNumber(item.repostCount);
  const replies = extractMetricNumber(item.replyCount) ||
    extractMetricNumber(item.reply_count);
  const views = extractMetricNumber(item.viewCount) ||
    extractMetricNumber(item.view_count);
  const quotes = extractMetricNumber(item.quoteCount) ||
    extractMetricNumber(item.quote_count);
  const rawScore = 0.5 +
    Math.min(
      (likes + retweets * 2 + replies + quotes + views / 10000) / 1000,
      0.49,
    );
  return Math.round(rawScore * 100) / 100;
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

function buildActorAttempts(
  usernames: string[],
  limitPerUser: number,
): ActorAttempt[] {
  const profileUrls = usernames.map((username) => `https://x.com/${username}`);
  const atHandles = usernames.map((username) => `@${username}`);
  const targetCount = Math.max(
    limitPerUser * usernames.length,
    usernames.length,
  );

  return [
    {
      name: "twitterHandles",
      input: {
        twitterHandles: usernames,
        maxItems: targetCount,
        sort: "Latest",
        onlyImage: false,
        onlyQuote: false,
        onlyVideo: false,
        includeSearchTerms: false,
      },
    },
    {
      name: "twitterHandlesWithAt",
      input: {
        twitterHandles: atHandles,
        maxItems: targetCount,
        sort: "Latest",
      },
    },
    {
      name: "searchTermsFromUsers",
      input: {
        searchTerms: usernames.map((username) => `from:${username}`),
        maxItems: targetCount,
        sort: "Latest",
      },
    },
    {
      name: "searchTermsPlainUsers",
      input: {
        searchTerms: usernames,
        maxItems: targetCount,
        sort: "Latest",
      },
    },
    {
      name: "startUrlsProfiles",
      input: {
        startUrls: profileUrls.map((url) => ({ url })),
        maxItems: targetCount,
      },
    },
    {
      name: "twitterUrlsProfiles",
      input: {
        twitterUrls: profileUrls,
        maxItems: targetCount,
      },
    },
    {
      name: "profileUrls",
      input: {
        profileUrls,
        maxItems: targetCount,
      },
    },
    {
      name: "userNames",
      input: {
        userNames: usernames,
        maxItems: targetCount,
      },
    },
  ];
}

function buildTimelineActorAttempt(
  usernames: string[],
  limitPerUser: number,
): ActorAttempt {
  return {
    name: "userTimeline",
    input: {
      username: usernames,
      count: limitPerUser,
      includeReplies: false,
      includeRetweets: true,
      batchSize: Math.min(Math.max(usernames.length, 1), 5),
      delayBetweenRequests: 1.5,
    },
  };
}

function buildApidojoProfileAttempt(
  usernames: string[],
  limitPerUser: number,
): ActorAttempt {
  return {
    name: "profileTweetsFallback",
    input: {
      twitterHandles: usernames,
      maxItems: Math.max(limitPerUser * usernames.length, usernames.length),
      getReplies: false,
      getAboutData: false,
    },
  };
}

function configuredTimelinePersonaIds() {
  return new Set(
    getScopedEnvOrDefault("X_TIMELINE_OVERRIDE_PERSONA_IDS", "kim_kardashian")
      .split(",")
      .map((value) => value.trim())
      .filter((value) => value.length > 0),
  );
}

function shouldUseTimelineActor(username: string) {
  const persona = resolvePersona(username);
  if (!persona) return false;

  return configuredTimelinePersonaIds().has(persona.personaId);
}

function flattenTimelineActorItems(items: ApifyItem[]): ApifyItem[] {
  return items.flatMap((item) => {
    const rootUsername = extractString(item.username) ??
      extractString(item.userName);
    const tweets = Array.isArray(item.tweets) ? item.tweets as ApifyItem[] : [];

    return tweets.map((tweet) => {
      const author = (tweet.user as Record<string, unknown> | undefined) ??
        (tweet.author as Record<string, unknown> | undefined) ?? {};
      const screenName = extractString(author.screen_name) ??
        extractString(author.screenName) ??
        rootUsername;
      const postId = extractString(tweet.id) ??
        extractString(tweet.postId) ??
        extractString(tweet.conversationId);
      const postUrl = extractString(tweet.postUrl) ??
        extractString(tweet.url) ??
        (screenName && postId
          ? `https://x.com/${screenName}/status/${postId}`
          : null);

      return {
        ...tweet,
        authorUsername: screenName,
        userName: screenName,
        screen_name: screenName,
        id_str: postId,
        fullText: extractString(tweet.text) ?? extractString(tweet.postText),
        url: postUrl,
        createdAt: tweet.created_at ?? tweet.createdAt ?? tweet.timestamp,
        favorite_count: tweet.favorite_count ??
          tweet.favoriteCount ??
          tweet.favouriteCount,
        retweet_count: tweet.retweet_count ??
          tweet.retweetCount ??
          tweet.repostCount,
        reply_count: tweet.reply_count ?? tweet.replyCount,
        quote_count: tweet.quote_count ?? tweet.quoteCount,
      } satisfies ApifyItem;
    });
  });
}

function hasUsefulItems(items: ApifyItem[]): boolean {
  return items.some((item) => {
    if (item.noResults === true) return false;
    return Boolean(
      extractString(item.fullText) ??
        extractString(item.text) ??
        extractString(item.description) ??
        extractString(item.url) ??
        extractString(item.twitterUrl),
    );
  });
}

async function fetchRunLog(
  token: string,
  runId: string,
): Promise<string | null> {
  const response = await fetch(
    `https://api.apify.com/v2/actor-runs/${runId}/log?token=${token}`,
  );
  if (!response.ok) {
    return null;
  }

  const text = await response.text();
  const trimmed = text.trim();
  if (!trimmed) return null;

  return trimmed.split("\n").slice(-40).join("\n");
}

async function runSingleAttempt(
  token: string,
  actorId: string,
  attempt: ActorAttempt,
) {
  const metric = createProviderMetricContext(
    "ingest-x-posts",
    "x_ingest_actor",
    `apify:${actorId}`,
    {
      attemptName: attempt.name,
    },
  );
  const encodedActorId = encodeURIComponent(actorId);
  const runResponse = await fetch(
    `https://api.apify.com/v2/acts/${encodedActorId}/runs?token=${token}&waitForFinish=120`,
    {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
      },
      body: JSON.stringify(attempt.input),
    },
  );

  if (!runResponse.ok) {
    const text = await runResponse.text();
    const quotaExceeded = text.includes("Monthly usage hard limit exceeded");
    logProviderMetricFailure(metric, text || "actor run start failed", {
      status: quotaExceeded ? "QUOTA_EXCEEDED" : "RUN_START_FAILED",
    });
    return {
      summary: {
        name: attempt.name,
        status: quotaExceeded ? "QUOTA_EXCEEDED" : "RUN_START_FAILED",
        statusMessage: text,
        itemCount: 0,
      } satisfies ActorAttemptSummary,
      items: [] as ApifyItem[],
    };
  }

  const runPayload = await runResponse.json();
  const run = runPayload?.data as Record<string, unknown> | undefined;
  const runId = extractString(run?.id);
  const status = extractString(run?.status) ?? "UNKNOWN";
  const statusMessage = extractString(run?.statusMessage);

  if (status !== "SUCCEEDED") {
    const logTail = runId ? await fetchRunLog(token, runId) : null;
    logProviderMetricFailure(
      metric,
      statusMessage ?? logTail ?? "Actor run did not succeed",
      {
        status,
        runId,
      },
    );
    return {
      summary: {
        name: attempt.name,
        status,
        statusMessage: statusMessage ?? logTail ?? "Actor run did not succeed",
        itemCount: 0,
      } satisfies ActorAttemptSummary,
      items: [] as ApifyItem[],
    };
  }

  const datasetId = extractString(run?.defaultDatasetId);
  if (!datasetId) {
    logProviderMetricFailure(
      metric,
      "Run succeeded but no default dataset was produced",
      {
        status,
        runId,
      },
    );
    return {
      summary: {
        name: attempt.name,
        status,
        statusMessage: "Run succeeded but no default dataset was produced",
        itemCount: 0,
      } satisfies ActorAttemptSummary,
      items: [] as ApifyItem[],
    };
  }

  const itemsResponse = await fetch(
    `https://api.apify.com/v2/datasets/${datasetId}/items?token=${token}&format=json&clean=true`,
  );
  if (!itemsResponse.ok) {
    const text = await itemsResponse.text();
    logProviderMetricFailure(metric, text || "dataset fetch failed", {
      status: "DATASET_FETCH_FAILED",
      runId,
      datasetId,
    });
    return {
      summary: {
        name: attempt.name,
        status: "DATASET_FETCH_FAILED",
        statusMessage: text,
        itemCount: 0,
      } satisfies ActorAttemptSummary,
      items: [] as ApifyItem[],
    };
  }

  const itemsPayload = await itemsResponse.json();
  const items = Array.isArray(itemsPayload) ? itemsPayload as ApifyItem[] : [];
  logProviderMetricSuccess(metric, {
    status,
    runId,
    datasetId,
    itemCount: items.length,
  });

  return {
    summary: {
      name: attempt.name,
      status,
      statusMessage,
      itemCount: items.length,
    } satisfies ActorAttemptSummary,
    items,
  };
}

function normalizePost(
  item: ApifyItem,
  contentSafety: ContentSafetyStats,
): NormalizedPost | null {
  const rawAuthorUsername = extractAuthorUsername(item);
  if (!rawAuthorUsername) return null;

  const persona = resolvePersona(rawAuthorUsername);
  if (!persona) return null;

  const provisionalUrl = extractString(item.url) ??
    extractString(item.twitterUrl);
  const postId = extractPostId(item, provisionalUrl);
  if (!postId) return null;

  const content = extractContent(item);
  if (!content) return null;
  if (isLowQualityContent(item, content)) return null;

  const contentSafetyResult = sanitizeExternalContent(content, {
    maxLength: 320,
  });
  if (contentSafetyResult.blocked || !contentSafetyResult.text) {
    contentSafety.blocked += 1;
    return null;
  }
  if (contentSafetyResult.sanitized) {
    contentSafety.sanitized += 1;
  }

  const publishedAt = extractPublishedAt(item);
  if (!publishedAt) return null;

  const sourceUrl = normalizeSourceUrl(
    extractSourceUrl(item, rawAuthorUsername, postId),
  );
  const mediaUrls = normalizeMediaUrls(extractMediaUrls(item));
  const videoUrl = normalizeAssetUrl(extractVideoUrl(item));

  return {
    id: postId,
    personaId: persona.personaId,
    content: contentSafetyResult.text,
    sourceType: "x",
    sourceUrl,
    topic: null,
    importanceScore: computeImportanceScore(item),
    mediaUrls,
    videoUrl,
    publishedAt,
    rawAuthorUsername,
    rawPayload: item,
  };
}

async function runActor(
  token: string,
  usernames: string[],
  limitPerUser: number,
): Promise<ActorRunResult> {
  const actorId = getScopedEnvOrDefault(
    "APIFY_ACTOR_ID",
    "quacker~twitter-scraper",
  );
  const attempts = buildActorAttempts(usernames, limitPerUser);
  const summaries: ActorAttemptSummary[] = [];

  for (const attempt of attempts) {
    const result = await runSingleAttempt(token, actorId, attempt);
    summaries.push(result.summary);

    if (result.summary.status === "QUOTA_EXCEEDED") {
      return {
        actorId,
        matchedAttempt: null,
        summaries,
        items: [],
        blockedReason: result.summary.statusMessage,
      };
    }

    if (result.summary.status === "SUCCEEDED" && hasUsefulItems(result.items)) {
      return {
        actorId,
        matchedAttempt: attempt.name,
        summaries,
        items: result.items,
        blockedReason: null,
      };
    }
  }

  return {
    actorId,
    matchedAttempt: null,
    summaries,
    items: [] as ApifyItem[],
    blockedReason: null,
  };
}

async function runTimelineActor(
  token: string,
  usernames: string[],
  limitPerUser: number,
): Promise<ActorRunResult> {
  const actorChain = [
    {
      actorId: getScopedEnvOrDefault(
        "APIFY_TIMELINE_ACTOR_ID",
        "logical_scrapers/x-twitter-user-profile-tweets-scraper",
      ),
      attempt: buildTimelineActorAttempt(usernames, limitPerUser),
      transformItems: flattenTimelineActorItems,
    },
    {
      actorId: getScopedEnvOrDefault(
        "APIFY_PROFILE_FALLBACK_ACTOR_ID",
        "apidojo/twitter-profile-scraper",
      ),
      attempt: buildApidojoProfileAttempt(usernames, limitPerUser),
      transformItems: (items: ApifyItem[]) => items,
    },
  ];

  const summaries: ActorAttemptSummary[] = [];

  for (const strategy of actorChain) {
    const result = await runSingleAttempt(
      token,
      strategy.actorId,
      strategy.attempt,
    );
    const transformedItems = strategy.transformItems(result.items);

    summaries.push({
      ...result.summary,
      name: `${strategy.actorId}:${strategy.attempt.name}`,
      itemCount: transformedItems.length,
    });

    if (result.summary.status === "QUOTA_EXCEEDED") {
      return {
        actorId: strategy.actorId,
        matchedAttempt: null,
        summaries,
        items: [],
        blockedReason: result.summary.statusMessage,
      };
    }

    if (
      result.summary.status === "SUCCEEDED" && hasUsefulItems(transformedItems)
    ) {
      return {
        actorId: strategy.actorId,
        matchedAttempt: strategy.attempt.name,
        summaries,
        items: transformedItems,
        blockedReason: null,
      };
    }

    const strategyIndex = actorChain.indexOf(strategy);
    const nextStrategy = actorChain[strategyIndex + 1];
    if (nextStrategy && result.summary.status !== "QUOTA_EXCEEDED") {
      logProviderMetricFallback(
        "ingest-x-posts",
        "x_ingest_actor",
        `apify:${strategy.actorId}`,
        `apify:${nextStrategy.actorId}`,
        {
          reason: result.summary.status,
          attemptName: strategy.attempt.name,
        },
      );
    }
  }

  return {
    actorId: actorChain[0].actorId,
    matchedAttempt: null,
    summaries,
    items: [],
    blockedReason: null,
  };
}

Deno.serve(async (request) => {
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
    const apifyToken = getOptionalScopedEnv("APIFY_TOKEN");

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

    if (!apifyToken) {
      logEdgeFailure(
        observation,
        "request_failed",
        "Missing environment variables",
      );
      return Response.json(
        { error: "Missing environment variables" },
        { status: 500, headers: corsHeaders },
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

      const timelineUsernames = usernames.filter((username) =>
        shouldUseTimelineActor(username)
      );
      const defaultActorUsernames = usernames.filter((username) =>
        !shouldUseTimelineActor(username)
      );

      const executions: ActorExecution[] = [];

      if (defaultActorUsernames.length > 0) {
        const result = await runActor(
          apifyToken,
          defaultActorUsernames,
          limitPerUser,
        );
        executions.push({
          actorId: result.actorId,
          matchedAttempt: result.matchedAttempt,
          usernames: defaultActorUsernames,
          summaries: result.summaries,
          items: result.items,
          blockedReason: result.blockedReason,
        });
      }

      if (timelineUsernames.length > 0) {
        const result = await runTimelineActor(
          apifyToken,
          timelineUsernames,
          limitPerUser,
        );
        executions.push({
          actorId: result.actorId,
          matchedAttempt: result.matchedAttempt,
          usernames: timelineUsernames,
          summaries: result.summaries,
          items: result.items,
          blockedReason: result.blockedReason,
        });
      }

      const items = executions.flatMap((execution) => execution.items);
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
          totalFetched: items.length,
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
            totalFetched: items.length,
            maxUsernamesPerRun: costControls.maxXUsernamesPerRun,
            maxPostsPerUser: costControls.maxXPostsPerUser,
            sample: items.slice(0, 3),
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
        items
          .map((item) => normalizePost(item, contentSafety))
          .filter((item): item is NormalizedPost => item !== null),
        limitPerUser,
      );

      if (contentSafety.blocked > 0 || contentSafety.sanitized > 0) {
        logEdgeEvent("ingest-x-posts", "content_safety_applied", {
          blocked: contentSafety.blocked,
          sanitized: contentSafety.sanitized,
          fetchedItems: items.length,
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
      const skipped = items.length - posts.length;

      await completePipelineJob(supabase, "ingest-x-posts", lock.ownerId, true);
      logEdgeSuccess(observation, "job_succeeded", {
        actorCount: executions.length,
        totalFetched: items.length,
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
          totalFetched: items.length,
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
