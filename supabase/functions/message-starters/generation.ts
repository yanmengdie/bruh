import { isTerminalAnthropicError } from "../_shared/anthropic.ts";
import { sanitizeGeneratedText } from "../_shared/content_safety.ts";
import type { LLMGenerationMode } from "../_shared/cost_controls.ts";
import { normalizeAssetUrl } from "../_shared/media.ts";
import { asString, defaultStarterMessage } from "../_shared/news.ts";
import { logEdgeError, logEdgeEvent } from "../_shared/observability.ts";
import {
  createProviderMetricContext,
  logProviderMetricFailure,
  logProviderMetricFallback,
  logProviderMetricSkipped,
  logProviderMetricSuccess,
} from "../_shared/provider_metrics.ts";
import { resolvePersonaById } from "../_shared/personas.ts";
import {
  personaFewShotExamples,
  personaImageStyle,
  personaRolePrompt,
} from "../_shared/persona_skills.ts";
import type { CandidateStarter } from "./types.ts";

function cleanStarterText(text: string) {
  const cleaned = text
    .split("\n")
    .map((line) => line.trim())
    .filter((line) => {
      const lower = line.toLowerCase();
      if (!lower) return false;
      return ![
        "i'm kiro",
        "i am kiro",
        "i'm an ai assistant",
        "i am an ai assistant",
        "i don't roleplay",
        "i do not roleplay",
        "i can't discuss that",
        "i cannot discuss that",
      ].some((prefix) => lower.startsWith(prefix));
    })
    .join(" ")
    .replace(/\s+/g, " ")
    .trim();

  return sanitizeGeneratedText(cleaned, { maxLength: 160 });
}

function safeStarterFallback(personaId: string, title: string) {
  const fallback = sanitizeGeneratedText(
    defaultStarterMessage(personaId, title),
    { maxLength: 160 },
  );
  if (!fallback.blocked && fallback.text) {
    return fallback.text;
  }

  const persona = resolvePersonaById(personaId);
  return persona?.primaryLanguage === "en"
    ? "The real implication here is bigger than the headline."
    : "这事真正的影响比 headline 还大。";
}

function extractOpenAICompatibleContent(value: unknown) {
  if (typeof value === "string") return value.trim();
  if (!Array.isArray(value)) return "";

  return value
    .map((item) => {
      const block = item as Record<string, unknown>;
      return asString(block.text ?? block.content);
    })
    .filter((item) => item.length > 0)
    .join("\n")
    .trim();
}

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

function buildStarterImagePrompt(
  personaId: string,
  item: CandidateStarter,
  starterText: string,
) {
  const persona = resolvePersonaById(personaId);
  if (!persona) return "";

  return [
    `Create the image ${persona.displayName} would casually attach while texting a friend about this news.`,
    "This is a contextual image attached to a chat message, not a UI screenshot, not a meme template, and not a poster.",
    `Persona visual taste: ${personaImageStyle(persona.personaId)}`,
    `Message text: ${starterText}`,
    `Headline: ${item.event.title}`,
    `Summary: ${item.event.summary}`,
    `Category: ${item.event.category}`,
    "Show one concrete real-world scene, object, location, or moment implied by the message and the news.",
    "If the message implies a place, meeting, stage, locker room, office, arena, rally, product, or travel scene, visualize that directly.",
    "Prefer a candid editorial or documentary feel over generic concept art.",
    "No text overlays, captions, watermarks, screenshots, phone frames, chat bubbles, or split panels.",
  ].join("\n\n");
}

async function generateStarterImageWithNanoBanana(
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
    signal: AbortSignal.timeout(12_000),
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

export async function maybeGenerateStarterImage(
  nanoBananaApiKey: string | undefined,
  nanoBananaBaseUrl: string,
  nanoBananaModel: string,
  personaId: string,
  item: CandidateStarter,
  starterText: string,
) {
  if (!nanoBananaApiKey) {
    logProviderMetricSkipped(
      "message-starters",
      "starter_image",
      "nano_banana",
      {
        personaId,
        eventId: item.event.id,
        reason: "missing_api_key",
      },
    );
    return null;
  }

  const prompt = buildStarterImagePrompt(personaId, item, starterText);
  if (!prompt) return null;

  const metric = createProviderMetricContext(
    "message-starters",
    "starter_image",
    "nano_banana",
    {
      personaId,
      eventId: item.event.id,
      model: nanoBananaModel,
    },
  );
  try {
    const imageUrl = await generateStarterImageWithNanoBanana(
      nanoBananaApiKey,
      nanoBananaBaseUrl,
      nanoBananaModel,
      prompt,
    );
    logProviderMetricSuccess(metric);
    return imageUrl;
  } catch (error) {
    logProviderMetricFailure(metric, error);
    logEdgeError("message-starters", "starter_image_generation_failed", error, {
      personaId,
      eventId: item.event.id,
    });
    return null;
  }
}

async function generateSingleStarterText(
  openaiApiKey: string | undefined,
  openaiBaseUrl: string,
  openaiModel: string,
  anthropicApiKey: string | undefined,
  anthropicBaseUrl: string,
  anthropicModels: string[],
  personaId: string,
  item: CandidateStarter,
  topSummary: string,
) {
  const fallback = safeStarterFallback(personaId, item.event.title);
  const persona = resolvePersonaById(personaId);
  if (!persona) return fallback;

  const system = [
    `You are ${persona.displayName}.`,
    personaRolePrompt(personaId),
    "Reply like a real person texting a friend about a piece of news.",
    "Exactly 1 sentence, max 24 words.",
    "Lead with your take, not a summary.",
    "Avoid phrases like 'big story today', 'huge headline today', 'worth watching', or 'worth noting'.",
    "No bullet points. No hashtags. No AI disclaimers.",
    "Examples of the desired style:",
    personaFewShotExamples(personaId),
  ].join(" ");

  const prompt = [
    `Headline: ${item.event.title}`,
    `Summary: ${item.event.summary}`,
    `Category: ${item.event.category}`,
    `Why this was selected: ${item.selectionReasons.join(", ")}`,
    topSummary ? `Broader top news context:\n${topSummary}` : "",
    "Write the first text you'd send me about this.",
  ].filter((value) => value.length > 0).join("\n\n");

  if (openaiApiKey) {
    const metric = createProviderMetricContext(
      "message-starters",
      "starter_text",
      "openai_compatible",
      {
        personaId,
        eventId: item.event.id,
        model: openaiModel,
      },
    );
    try {
      const openAIResponse = await fetch(`${openaiBaseUrl}/chat/completions`, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${openaiApiKey}`,
        },
        body: JSON.stringify({
          model: openaiModel,
          messages: [
            { role: "system", content: system },
            { role: "user", content: prompt },
          ],
          max_tokens: 120,
          temperature: 0.4,
        }),
      });

      if (openAIResponse.ok) {
        const payload = await openAIResponse.json();
        const cleaned = cleanStarterText(
          extractOpenAICompatibleContent(
            payload.choices?.[0]?.message?.content,
          ),
        );
        if (!cleaned.blocked && cleaned.text) {
          logProviderMetricSuccess(metric);
          if (cleaned.sanitized) {
            logEdgeEvent("message-starters", "starter_text_sanitized", {
              personaId,
              eventId: item.event.id,
              provider: "openai_compatible",
              reasons: cleaned.reasons,
            });
          }
          return cleaned.text;
        }

        if (cleaned.blocked) {
          logProviderMetricFailure(
            metric,
            "starter text blocked by content safety",
          );
          logEdgeEvent("message-starters", "starter_text_blocked", {
            personaId,
            eventId: item.event.id,
            provider: "openai_compatible",
            reasons: cleaned.reasons,
          });
        }
      } else {
        logProviderMetricFailure(metric, await openAIResponse.text());
      }
    } catch (error) {
      logProviderMetricFailure(metric, error);
      // Fall through to Anthropic and then deterministic fallback.
    }
  } else {
    logProviderMetricSkipped(
      "message-starters",
      "starter_text",
      "openai_compatible",
      {
        personaId,
        eventId: item.event.id,
        reason: "missing_api_key",
      },
    );
  }

  if (anthropicApiKey) {
    if (openaiApiKey) {
      logProviderMetricFallback(
        "message-starters",
        "starter_text",
        "openai_compatible",
        "anthropic",
        {
          personaId,
          eventId: item.event.id,
          reason: "openai_unavailable_or_invalid",
        },
      );
    }
    for (const anthropicModel of anthropicModels) {
      const metric = createProviderMetricContext(
        "message-starters",
        "starter_text",
        "anthropic",
        {
          personaId,
          eventId: item.event.id,
          model: anthropicModel,
        },
      );
      try {
        const anthropicResponse = await fetch(
          `${anthropicBaseUrl}/v1/messages`,
          {
            method: "POST",
            headers: {
              "Content-Type": "application/json",
              "x-api-key": anthropicApiKey,
              "anthropic-version": "2023-06-01",
            },
            body: JSON.stringify({
              model: anthropicModel,
              max_tokens: 120,
              temperature: 0.4,
              system,
              messages: [{
                role: "user",
                content: prompt,
              }],
            }),
          },
        );

        if (anthropicResponse.ok) {
          const payload = await anthropicResponse.json();
          const content = Array.isArray(payload.content)
            ? payload.content
              .filter((block: Record<string, unknown>) => block.type === "text")
              .map((block: Record<string, unknown>) => asString(block.text))
              .join(" ")
              .trim()
            : "";

          const cleaned = cleanStarterText(content);
          if (!cleaned.blocked && cleaned.text) {
            logProviderMetricSuccess(metric);
            if (cleaned.sanitized) {
              logEdgeEvent("message-starters", "starter_text_sanitized", {
                personaId,
                eventId: item.event.id,
                provider: "anthropic",
                model: anthropicModel,
                reasons: cleaned.reasons,
              });
            }
            return cleaned.text;
          }

          if (cleaned.blocked) {
            logProviderMetricFailure(
              metric,
              "starter text blocked by content safety",
            );
            logEdgeEvent("message-starters", "starter_text_blocked", {
              personaId,
              eventId: item.event.id,
              provider: "anthropic",
              model: anthropicModel,
              reasons: cleaned.reasons,
            });
          }
          continue;
        }

        const errorText = await anthropicResponse.text();
        logProviderMetricFailure(metric, errorText);
        if (isTerminalAnthropicError(errorText)) {
          break;
        }
      } catch (error) {
        logProviderMetricFailure(metric, error);
        if (isTerminalAnthropicError(error)) {
          break;
        }
      }
    }
  } else {
    logProviderMetricSkipped("message-starters", "starter_text", "anthropic", {
      personaId,
      eventId: item.event.id,
      reason: "missing_api_key",
    });
  }

  logProviderMetricFallback(
    "message-starters",
    "starter_text",
    "provider_chain",
    "deterministic",
    {
      personaId,
      eventId: item.event.id,
      reason: "provider_unavailable_or_invalid",
    },
  );
  return fallback;
}

export async function generateStarterTexts(
  openaiApiKey: string | undefined,
  openaiBaseUrl: string,
  openaiModel: string,
  anthropicApiKey: string | undefined,
  anthropicBaseUrl: string,
  anthropicModels: string[],
  personaId: string,
  items: CandidateStarter[],
  topSummary: string,
  llmGenerationMode: LLMGenerationMode = "enabled",
) {
  if (items.length === 0) return new Map<string, string>();

  const fallbackTexts = new Map(
    items.map((
      item,
    ) => [item.event.id, safeStarterFallback(personaId, item.event.title)]),
  );
  if (llmGenerationMode !== "enabled") {
    return fallbackTexts;
  }

  const generatedEntries = await Promise.all(items.map(async (item) => {
    try {
      return [
        item.event.id,
        await generateSingleStarterText(
          openaiApiKey,
          openaiBaseUrl,
          openaiModel,
          anthropicApiKey,
          anthropicBaseUrl,
          anthropicModels,
          personaId,
          item,
          topSummary,
        ),
      ] as const;
    } catch {
      return [
        item.event.id,
        fallbackTexts.get(item.event.id) ??
          defaultStarterMessage(personaId, item.event.title),
      ] as const;
    }
  }));

  return new Map(generatedEntries);
}
