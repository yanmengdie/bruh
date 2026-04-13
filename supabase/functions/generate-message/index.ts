import { createClient } from "jsr:@supabase/supabase-js@2";
import {
  contractHeaders,
  isAcceptedContractCompatible,
  requestedClientVersion,
} from "../_shared/api_contract.ts";
import { sanitizeGeneratedText } from "../_shared/content_safety.ts";
import { resolveCostControls } from "../_shared/cost_controls.ts";
import { corsHeaders } from "../_shared/cors.ts";
import {
  getOptionalScopedEnv,
  getScopedEnvOrDefault,
  resolveSupabaseServiceConfig,
} from "../_shared/environment.ts";
import { normalizeAssetUrl, normalizeSourceUrl } from "../_shared/media.ts";
import { buildImagePrompt } from "../_shared/image_prompt.ts";
import {
  classifyError,
  createObservationContext,
  logEdgeError,
  logEdgeEvent,
  logEdgeFailure,
  logEdgeStart,
  logEdgeSuccess,
  responseHeadersWithRequestId,
} from "../_shared/observability.ts";
import {
  createProviderMetricContext,
  logProviderMetricFailure,
  logProviderMetricFallback,
  logProviderMetricSkipped,
  logProviderMetricSuccess,
} from "../_shared/provider_metrics.ts";
import { resolvePersonaById } from "../_shared/personas.ts";
import { fallbackPersonaReply } from "./fallbacks.ts";
import { asString, normalizeBoolean } from "./helpers.ts";
import {
  buildCombinedNewsContext,
  buildPersonaStyleGuide,
  buildSystemPrompt,
  normalizeConversation,
  normalizeInterests,
  resolveSharedSourceUrl,
  selectContext,
  selectRelevantNews,
} from "./prompting.ts";
import { generatePersonaReplyWithProviders } from "./providers.ts";
import type { ContextRow, PersonaNewsScoreRow } from "./types.ts";
import {
  buildVoicePlan,
  normalizeVoiceError,
  synthesizeVoiceReplyWithRetries,
} from "./voice.ts";

function extractImageUrl(payload: Record<string, unknown>) {
  const collectionCandidates = [
    payload.data,
    payload.images,
    payload.output,
    payload.results,
  ];

  for (const candidate of collectionCandidates) {
    if (!Array.isArray(candidate)) continue;
    for (const item of candidate) {
      const row = item as Record<string, unknown>;
      const imageUrl = asString(row.url ?? row.image_url ?? row.imageUrl);
      if (imageUrl) return imageUrl;
    }
  }

  return asString(payload.url ?? payload.image_url ?? payload.imageUrl);
}

function genericSafeReply(primaryLanguage: string) {
  return primaryLanguage === "en"
    ? "Say the concrete part first."
    : "先说具体一点。";
}

async function generateImageWithNanoBanana(
  apiKey: string,
  baseUrl: string,
  model: string,
  prompt: string,
) {
  const response = await fetch(`${baseUrl}/images/generations`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${apiKey}`,
    },
    body: JSON.stringify({
      model,
      prompt,
      aspect_ratio: "1:1",
      image_size: "1k",
      response_format: "url",
    }),
  });

  if (!response.ok) {
    throw new Error(`Nano Banana request failed: ${await response.text()}`);
  }

  const payload = await response.json();
  const imageUrl = normalizeAssetUrl(extractImageUrl(payload));
  if (!imageUrl) {
    throw new Error("Nano Banana returned no image URL");
  }

  return imageUrl;
}

Deno.serve(async (request) => {
  const baseResponseHeaders = contractHeaders(
    corsHeaders,
    "generate-message.v1",
  );

  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: baseResponseHeaders });
  }

  const observation = createObservationContext("generate-message");
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
    if (!isAcceptedContractCompatible(request, "generate-message.v1")) {
      logEdgeSuccess(observation, "request_rejected", {
        status: 412,
        clientVersion,
      });
      return Response.json(
        {
          error: "Requested contract is incompatible with generate-message.v1",
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

    const { projectUrl: url, serviceRoleKey } = resolveSupabaseServiceConfig();
    const openaiApiKey = getOptionalScopedEnv("OPENAI_API_KEY");
    const openaiBaseUrl = getScopedEnvOrDefault(
      "OPENAI_BASE_URL",
      "https://api.openai.com/v1",
    ).replace(/\/$/, "");
    const openaiModel = getScopedEnvOrDefault("OPENAI_MODEL", "gpt-4.1-mini");
    const nanoBananaApiKey = getOptionalScopedEnv("NANO_BANANA_API_KEY");
    const nanoBananaBaseUrl = getScopedEnvOrDefault(
      "NANO_BANANA_BASE_URL",
      "https://ccodezh.com/v1",
    ).replace(/\/$/, "");
    const nanoBananaModel = getScopedEnvOrDefault(
      "NANO_BANANA_MODEL",
      "nano-banana",
    );
    const voiceApiKey = asString(getOptionalScopedEnv("VOICE_API_KEY")) || null;
    const voiceApiBaseUrl = (
      getOptionalScopedEnv("VOICE_API_BASE_URL") ??
        "https://uu36540-775678b2e148.bjb2.seetacloud.com:8443/api"
    ).replace(/\/$/, "");

    const body = await request.json().catch(() => ({})) as Record<
      string,
      unknown
    >;
    const costControls = resolveCostControls();
    const personaId = asString(body.personaId);
    const userMessage = asString(body.userMessage);
    const conversation = normalizeConversation(body.conversation);
    const newsContext = asString(body.newsContext);
    const userInterests = normalizeInterests(body.userInterests);
    const requestImage = normalizeBoolean(body.requestImage);
    const forceVoice = normalizeBoolean(body.forceVoice);
    const debugProviders = normalizeBoolean(body.debugProviders);

    if (!personaId) {
      logEdgeSuccess(observation, "request_rejected", {
        status: 400,
        clientVersion,
      });
      return Response.json(
        { error: "personaId is required", errorCategory: "validation" },
        { status: 400, headers: responseHeaders },
      );
    }

    if (!userMessage) {
      logEdgeSuccess(observation, "request_rejected", {
        status: 400,
        clientVersion,
      });
      return Response.json(
        { error: "userMessage is required", errorCategory: "validation" },
        { status: 400, headers: responseHeaders },
      );
    }

    const persona = resolvePersonaById(personaId);
    if (!persona) {
      logEdgeSuccess(observation, "request_rejected", {
        status: 400,
        clientVersion,
      });
      return Response.json(
        { error: "Unknown personaId", errorCategory: "validation" },
        { status: 400, headers: responseHeaders },
      );
    }

    const supabase = createClient(url, serviceRoleKey);
    const { data: feedItems, error: feedError } = await supabase
      .from("feed_items")
      .select("id, persona_id, content, topic, importance_score, published_at")
      .order("published_at", { ascending: false })
      .limit(20);

    if (feedError && !feedError.message.includes("feed_items")) {
      throw new Error(feedError.message);
    }

    let rows = (feedItems ?? []) as ContextRow[];

    if (rows.length === 0) {
      const { data: sourcePosts, error: sourceError } = await supabase
        .from("source_posts")
        .select(
          "id, persona_id, content, topic, importance_score, published_at",
        )
        .order("published_at", { ascending: false })
        .limit(20);

      if (sourceError) {
        throw new Error(sourceError.message);
      }

      rows = (sourcePosts ?? []) as ContextRow[];
    }

    const { data: personaNewsRows, error: personaNewsError } = await supabase
      .from("persona_news_scores")
      .select(`
        score,
        news_events (
          id,
          title,
          summary,
          category,
          interest_tags,
          representative_url,
          importance_score,
          published_at
        )
      `)
      .eq("persona_id", personaId)
      .order("score", { ascending: false })
      .limit(20);

    if (
      personaNewsError &&
      !personaNewsError.message.includes("persona_news_scores")
    ) {
      throw new Error(personaNewsError.message);
    }

    const relevantNews = selectRelevantNews(
      (personaNewsRows ?? []) as PersonaNewsScoreRow[],
      userInterests,
    );

    const selected = selectContext(
      rows,
      personaId,
      userMessage,
      persona.triggerKeywords,
    );
    const selectedContextIds = selected.map((row) => row.id);
    const relevantNewsIds = relevantNews.map((row) => row.id);
    const combinedNewsContext = buildCombinedNewsContext(
      newsContext,
      relevantNews,
    );
    const styleGuide = buildPersonaStyleGuide(persona);

    const canGenerateMessageImage = requestImage &&
      costControls.messageImageMode === "enabled";
    const system = buildSystemPrompt(
      persona,
      selected,
      combinedNewsContext,
      canGenerateMessageImage,
    );
    const generation = costControls.llmGenerationMode === "enabled"
      ? await generatePersonaReplyWithProviders({
        persona,
        system,
        styleGuide,
        conversation,
        userMessage,
        openaiApiKey: openaiApiKey ?? undefined,
        openaiBaseUrl,
        openaiModel,
        selectedContextIds,
        relevantNewsIds,
        requestId,
      })
      : {
        content: null,
        providerErrors: [
          "[cost-control] llm generation disabled by BRUH_LLM_GENERATION_MODE",
        ],
        lastError: null,
        usedProvider: null,
        usedOpenAIModel: null,
        usedAnthropicModel: null,
      };

    if (costControls.llmGenerationMode !== "enabled") {
      logEdgeEvent("generate-message", "llm_generation_skipped", {
        requestId,
        personaId,
        llmGenerationMode: costControls.llmGenerationMode,
      });
    }

    let content = generation.content ?? "";
    const providerErrors = generation.providerErrors;
    let usedFallback = false;
    let contentSource: "provider" | "fallback" | "generic" = "provider";
    const lastError = generation.lastError;
    const usedProvider = generation.usedProvider;
    const usedOpenAIModel = generation.usedOpenAIModel;
    const usedAnthropicModel = generation.usedAnthropicModel;

    if (!content) {
      content = fallbackPersonaReply(
        persona,
        userMessage,
        selected,
        combinedNewsContext,
      );
      usedFallback = true;
      contentSource = "fallback";
      logProviderMetricFallback(
        "generate-message",
        "persona_reply",
        generation.usedProvider ?? "provider_chain",
        "deterministic",
        {
          requestId,
          personaId,
          providerErrorCount: providerErrors.length,
        },
      );
      logEdgeEvent("generate-message", "message_fallback_used", {
        requestId,
        personaId,
        lastError: lastError?.message ?? null,
        selectedContextIds,
        relevantNewsIds,
      });
    }

    const contentSafety = sanitizeGeneratedText(content, { maxLength: 240 });
    if (contentSafety.blocked) {
      const blockedSource = contentSource;
      const fallbackCandidate = contentSource === "provider"
        ? fallbackPersonaReply(
          persona,
          userMessage,
          selected,
          combinedNewsContext,
        )
        : genericSafeReply(persona.primaryLanguage);
      const fallbackSafety = sanitizeGeneratedText(fallbackCandidate, {
        maxLength: 240,
      });

      content = fallbackSafety.blocked || !fallbackSafety.text
        ? genericSafeReply(persona.primaryLanguage)
        : fallbackSafety.text;
      contentSource = contentSource === "provider" ? "fallback" : "generic";
      usedFallback = true;

      logEdgeEvent("generate-message", "content_safety_blocked", {
        requestId,
        personaId,
        source: blockedSource,
        reasons: contentSafety.reasons,
        originalLength: contentSafety.originalLength,
      });
    } else {
      content = contentSafety.text;
      if (contentSafety.sanitized) {
        logEdgeEvent("generate-message", "content_safety_sanitized", {
          requestId,
          personaId,
          source: contentSource,
          reasons: contentSafety.reasons,
          originalLength: contentSafety.originalLength,
          finalLength: contentSafety.finalLength,
        });
      }
    }

    let imageUrl: string | null = null;
    const sourceUrl = normalizeSourceUrl(
      resolveSharedSourceUrl(persona, userMessage, newsContext, relevantNews),
    );
    if (canGenerateMessageImage && nanoBananaApiKey) {
      const imageMetric = createProviderMetricContext(
        "generate-message",
        "message_image",
        "nano_banana",
        {
          requestId,
          personaId,
          model: nanoBananaModel,
        },
      );
      try {
        imageUrl = await generateImageWithNanoBanana(
          nanoBananaApiKey,
          nanoBananaBaseUrl,
          nanoBananaModel,
          buildImagePrompt(persona, userMessage, conversation),
        );
        logProviderMetricSuccess(imageMetric);
      } catch (error) {
        logProviderMetricFailure(imageMetric, error);
        logEdgeError("generate-message", "image_generation_failed", error, {
          requestId,
          personaId,
        });
        imageUrl = null;
      }
    } else if (canGenerateMessageImage) {
      logProviderMetricSkipped(
        "generate-message",
        "message_image",
        "nano_banana",
        {
          requestId,
          personaId,
          reason: "missing_api_key",
        },
      );
    }
    let audioUrl: string | null = null;
    let audioDuration: number | null = null;
    let voiceLabel: string | null = null;
    let audioError: string | null = null;
    let audioOnly = false;

    const voicePlan = buildVoicePlan(
      persona,
      content,
      requestImage,
      forceVoice,
      {
        ttsMode: costControls.ttsMode,
        maxCharacters: costControls.maxTTSCharacters,
      },
    );
    if (voicePlan.shouldGenerate) {
      const voiceMetric = createProviderMetricContext(
        "generate-message",
        "voice_reply",
        "tts_async",
        {
          requestId,
          personaId,
          voiceLabel: voicePlan.voiceLabel,
          speakerId: voicePlan.speakerId,
        },
      );
      try {
        const voiceReply = await synthesizeVoiceReplyWithRetries(
          voiceApiBaseUrl,
          voiceApiKey,
          voicePlan,
          content,
          forceVoice,
        );
        const normalizedAudioUrl = normalizeAssetUrl(voiceReply.audioUrl);
        if (!normalizedAudioUrl) {
          throw new Error("Voice synthesis returned an invalid audio URL");
        }
        audioUrl = normalizedAudioUrl;
        audioDuration = voiceReply.duration;
        voiceLabel = voiceReply.voiceLabel;
        audioOnly = true;
        logProviderMetricSuccess(voiceMetric);
      } catch (error) {
        audioError = normalizeVoiceError(error);
        logProviderMetricFailure(voiceMetric, error);
        logEdgeError("generate-message", "voice_generation_failed", error, {
          requestId,
          personaId,
        });
      }
    } else if (forceVoice || costControls.ttsMode !== "disabled") {
      logProviderMetricSkipped(
        "generate-message",
        "voice_reply",
        "tts_async",
        {
          requestId,
          personaId,
          reason: "voice_plan_disabled",
        },
      );
    }
    const generatedAt = new Date().toISOString();
    logEdgeSuccess(observation, "request_succeeded", {
      personaId,
      usedFallback,
      usedProvider,
      requestImage,
      forceVoice,
      llmGenerationMode: costControls.llmGenerationMode,
      ttsMode: costControls.ttsMode,
      messageImageMode: costControls.messageImageMode,
      audioGenerated: audioUrl !== null,
      imageGenerated: imageUrl !== null,
      selectedContextIds,
      relevantNewsIds,
      clientVersion,
    });

    return Response.json(
      {
        id: `msg-${crypto.randomUUID()}`,
        personaId,
        content,
        imageUrl,
        audioUrl,
        audioDuration,
        voiceLabel,
        audioError,
        audioOnly,
        sourceUrl,
        sourcePostIds: [...selectedContextIds, ...relevantNewsIds],
        generatedAt,
        ...(debugProviders
          ? {
            debug: {
              providerErrors,
              usedFallback,
              usedProvider,
              usedOpenAIModel,
              usedAnthropicModel,
              openaiModelTried: openaiApiKey ? openaiModel : null,
              anthropicModelsTried: [],
              selectedContextIds,
              relevantNewsIds,
            },
          }
          : {}),
      },
      { headers: responseHeaders },
    );
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
