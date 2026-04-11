import { createClient } from "jsr:@supabase/supabase-js@2";
import {
  contractHeaders,
  isAcceptedContractCompatible,
  requestedClientVersion,
} from "../_shared/api_contract.ts";
import { anthropicModelCandidates } from "../_shared/anthropic.ts";
import { resolveCostControls } from "../_shared/cost_controls.ts";
import { corsHeaders } from "../_shared/cors.ts";
import {
  getOptionalScopedEnv,
  getScopedEnvOrDefault,
  resolveSupabaseServiceConfig,
} from "../_shared/environment.ts";
import { resolveBackendFeatureFlags } from "../_shared/feature_flags.ts";
import { defaultStarterMessage, topNewsSummaryBlock } from "../_shared/news.ts";
import {
  classifyError,
  createObservationContext,
  logEdgeFailure,
  logEdgeStart,
  logEdgeSuccess,
  responseHeadersWithRequestId,
} from "../_shared/observability.ts";
import {
  generateStarterTexts,
  maybeGenerateStarterImage,
} from "./generation.ts";
import {
  collectSelectedStarters,
  normalizeInterests,
  pickStarterImageEventIds,
  resolveStarterSourceUrl,
} from "./selection.ts";
import type { PersonaScoreRow, StarterEventRow } from "./types.ts";

Deno.serve(async (request) => {
  const baseResponseHeaders = contractHeaders(
    corsHeaders,
    "message-starters.v1",
  );

  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: baseResponseHeaders });
  }

  const observation = createObservationContext("message-starters");
  const requestId = observation.requestId;
  const responseHeaders = responseHeadersWithRequestId(
    baseResponseHeaders,
    requestId,
  );
  const clientVersion = requestedClientVersion(request);
  logEdgeStart(observation, "request_started", {
    method: request.method,
    clientVersion,
  });

  try {
    if (!isAcceptedContractCompatible(request, "message-starters.v1")) {
      logEdgeSuccess(observation, "request_rejected", {
        status: 412,
        clientVersion,
      });
      return Response.json(
        {
          error: "Requested contract is incompatible with message-starters.v1",
          errorCategory: "validation",
        },
        { status: 412, headers: responseHeaders },
      );
    }

    if (request.method !== "POST") {
      logEdgeSuccess(observation, "request_rejected", {
        status: 405,
        clientVersion,
      });
      return Response.json(
        { error: "Method not allowed", errorCategory: "validation" },
        { status: 405, headers: responseHeaders },
      );
    }

    const { projectUrl, serviceRoleKey } = resolveSupabaseServiceConfig();
    const openaiApiKey = getOptionalScopedEnv("OPENAI_API_KEY");
    const openaiBaseUrl = getScopedEnvOrDefault(
      "OPENAI_BASE_URL",
      "https://api.openai.com/v1",
    ).replace(/\/$/, "");
    const openaiModel = getScopedEnvOrDefault("OPENAI_MODEL", "gpt-4.1-mini");
    const anthropicApiKey = getOptionalScopedEnv("ANTHROPIC_API_KEY");
    const anthropicBaseUrl = getScopedEnvOrDefault(
      "ANTHROPIC_BASE_URL",
      "https://api.anthropic.com",
    ).replace(/\/$/, "");
    const anthropicModels = anthropicModelCandidates(
      getOptionalScopedEnv("ANTHROPIC_MODEL"),
    );
    const nanoBananaApiKey = getOptionalScopedEnv("NANO_BANANA_API_KEY");
    const nanoBananaBaseUrl = getScopedEnvOrDefault(
      "NANO_BANANA_BASE_URL",
      "https://ccodezh.com/v1",
    ).replace(/\/$/, "");
    const nanoBananaModel = getScopedEnvOrDefault(
      "NANO_BANANA_MODEL",
      "nano-banana",
    );

    const body = await request.json().catch(() => ({})) as Record<
      string,
      unknown
    >;
    const userInterests = normalizeInterests(body.userInterests);
    const costControls = resolveCostControls();
    const featureFlags = resolveBackendFeatureFlags();
    const supabase = createClient(projectUrl, serviceRoleKey);

    const { data: eventRows, error: eventError } = await supabase
      .from("news_events")
      .select(
        "id, title, summary, category, interest_tags, representative_url, global_rank, is_global_top, published_at, importance_score",
      )
      .order("is_global_top", { ascending: false })
      .order("global_rank", { ascending: true, nullsFirst: false })
      .order("importance_score", { ascending: false })
      .limit(30);

    if (eventError && !eventError.message.includes("news_events")) {
      throw new Error(eventError.message);
    }

    const events = (eventRows ?? []) as StarterEventRow[];
    const topNews = events
      .filter((event) => event.is_global_top)
      .sort((left, right) =>
        (left.global_rank ?? 999) - (right.global_rank ?? 999)
      );

    const topSummary = topNewsSummaryBlock(topNews.map((event) => ({
      ...event,
      representative_source_name: "News",
    })));
    if (events.length === 0) {
      logEdgeSuccess(observation, "request_succeeded", {
        starterCount: 0,
        eventCount: 0,
        clientVersion,
      });
      return Response.json({ starters: [], topSummary }, {
        headers: responseHeaders,
      });
    }

    const { data: scoreRows, error: scoreError } = await supabase
      .from("persona_news_scores")
      .select("event_id, persona_id, score, reason_codes, matched_interests")
      .in("event_id", events.map((event) => event.id))
      .in("persona_id", featureFlags.enabledPersonaIds);

    if (scoreError && !scoreError.message.includes("persona_news_scores")) {
      throw new Error(scoreError.message);
    }

    const scoresByEvent = new Map<string, PersonaScoreRow[]>();
    for (const row of (scoreRows ?? []) as PersonaScoreRow[]) {
      const bucket = scoresByEvent.get(row.event_id) ?? [];
      bucket.push(row);
      scoresByEvent.set(row.event_id, bucket);
    }

    const selected = collectSelectedStarters(
      events,
      scoresByEvent,
      userInterests,
      {
        strategy: featureFlags.starterSelectionStrategy,
        allowedPersonaIds: new Set(featureFlags.enabledPersonaIds),
      },
    );
    const selectedStarterImageEventIds = pickStarterImageEventIds(
      selected,
      featureFlags.starterImageMode,
    );
    const starters = [];

    for (
      const personaId of [...new Set(selected.map((item) => item.personaId))]
        .sort()
    ) {
      const items = selected
        .filter((item) => item.personaId === personaId)
        .sort((left, right) =>
          Date.parse(left.event.published_at) -
          Date.parse(right.event.published_at)
        )
        .map((item) => ({
          event: item.event,
          score: item.score,
          selectionReasons: item.selectionReasons,
        }));

      const generatedTexts = await generateStarterTexts(
        openaiApiKey ?? undefined,
        openaiBaseUrl,
        openaiModel,
        anthropicApiKey ?? undefined,
        anthropicBaseUrl,
        anthropicModels,
        personaId,
        items,
        topSummary,
        costControls.llmGenerationMode,
      );
      const generatedImages = new Map(
        await Promise.all(
          items
            .filter((item) => selectedStarterImageEventIds.has(item.event.id))
            .map(async (item) =>
              [
                item.event.id,
                await maybeGenerateStarterImage(
                  nanoBananaApiKey ?? undefined,
                  nanoBananaBaseUrl,
                  nanoBananaModel,
                  personaId,
                  item,
                  generatedTexts.get(item.event.id) ??
                    defaultStarterMessage(personaId, item.event.title),
                ),
              ] as const
            ),
        ),
      );

      for (const item of items) {
        const sourceUrl = resolveStarterSourceUrl(
          personaId,
          item,
          featureFlags.starterSourceUrlMode,
        );
        starters.push({
          id: `starter-news-${personaId}-${item.event.id}`,
          personaId,
          text: generatedTexts.get(item.event.id) ??
            defaultStarterMessage(personaId, item.event.title),
          imageUrl: generatedImages.get(item.event.id) ?? null,
          sourceUrl,
          sourcePostIds: [item.event.id],
          createdAt: item.event.published_at,
          category: item.event.category,
          headline: item.event.title,
          isGlobalTop: item.event.is_global_top,
          selectionReasons: item.selectionReasons,
        });
      }
    }

    starters.sort((left, right) =>
      left.personaId.localeCompare(right.personaId) ||
      Date.parse(left.createdAt) - Date.parse(right.createdAt)
    );
    logEdgeSuccess(observation, "request_succeeded", {
      starterCount: starters.length,
      personaCount: new Set(starters.map((starter) => starter.personaId)).size,
      eventCount: events.length,
      selectedCount: selected.length,
      starterSelectionStrategy: featureFlags.starterSelectionStrategy,
      starterImageMode: featureFlags.starterImageMode,
      starterSourceUrlMode: featureFlags.starterSourceUrlMode,
      hasPersonaAllowlist: featureFlags.hasPersonaAllowlist,
      llmGenerationMode: costControls.llmGenerationMode,
      clientVersion,
    });

    return Response.json({ starters, topSummary }, {
      headers: responseHeaders,
    });
  } catch (error) {
    const errorCategory = classifyError(error);
    logEdgeFailure(observation, "request_failed", error, {
      clientVersion,
    });
    return Response.json(
      {
        error: error instanceof Error ? error.message : "Unknown error",
        errorCategory,
      },
      { status: 500, headers: responseHeaders },
    );
  }
});
