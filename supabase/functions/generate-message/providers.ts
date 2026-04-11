import { isTerminalAnthropicError } from "../_shared/anthropic.ts";
import { logEdgeEvent } from "../_shared/observability.ts";
import {
  createProviderMetricContext,
  logProviderMetricFailure,
  logProviderMetricFallback,
  logProviderMetricSkipped,
  logProviderMetricSuccess,
} from "../_shared/provider_metrics.ts";
import type { PersonaDefinition } from "../_shared/personas.ts";
import { asString, delay } from "./helpers.ts";
import { buildProviderMessages } from "./prompting.ts";
import type { ConversationTurn } from "./types.ts";

const MAX_GENERATION_RETRIES = 3;

export type ProviderGenerationResult = {
  content: string | null;
  providerErrors: string[];
  lastError: Error | null;
  usedProvider: "openai_compatible" | "anthropic" | null;
  usedOpenAIModel: string | null;
  usedAnthropicModel: string | null;
};

type ProviderGenerationParams = {
  persona: PersonaDefinition;
  system: string;
  styleGuide: string;
  conversation: ConversationTurn[];
  userMessage: string;
  openaiApiKey?: string;
  openaiBaseUrl: string;
  openaiModel: string;
  anthropicApiKey?: string;
  anthropicBaseUrl: string;
  anthropicModels: string[];
  selectedContextIds: string[];
  relevantNewsIds: string[];
  requestId?: string;
};

async function generateWithAnthropic(
  apiKey: string,
  baseUrl: string,
  model: string,
  persona: PersonaDefinition,
  system: string,
  styleGuide: string,
  conversation: ConversationTurn[],
  userMessage: string,
) {
  const response = await fetch(`${baseUrl}/v1/messages`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "x-api-key": apiKey,
      "anthropic-version": "2023-06-01",
    },
    body: JSON.stringify({
      model,
      max_tokens: 120,
      temperature: 0.85,
      system,
      messages: buildProviderMessages(
        persona,
        styleGuide,
        conversation,
        userMessage,
      ).map((message) => ({
        role: message.role,
        content: message.content,
      })),
    }),
  });

  if (!response.ok) {
    throw new Error(`Anthropic request failed: ${await response.text()}`);
  }

  const payload = await response.json();
  const content = Array.isArray(payload.content)
    ? payload.content
      .filter((block: Record<string, unknown>) => block.type === "text")
      .map((block: Record<string, unknown>) => asString(block.text))
      .join("\n")
      .trim()
    : "";

  if (!content) {
    throw new Error("Anthropic returned empty content");
  }

  return content;
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

async function generateWithOpenAICompatible(
  apiKey: string,
  baseUrl: string,
  model: string,
  persona: PersonaDefinition,
  system: string,
  styleGuide: string,
  conversation: ConversationTurn[],
  userMessage: string,
) {
  const response = await fetch(`${baseUrl}/chat/completions`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${apiKey}`,
    },
    body: JSON.stringify({
      model,
      messages: [
        { role: "system", content: system },
        ...buildProviderMessages(
          persona,
          styleGuide,
          conversation,
          userMessage,
        ),
      ],
      max_tokens: 120,
      temperature: 0.85,
    }),
  });

  if (!response.ok) {
    throw new Error(
      `OpenAI-compatible request failed: ${await response.text()}`,
    );
  }

  const payload = await response.json();
  const content = extractOpenAICompatibleContent(
    payload.choices?.[0]?.message?.content,
  );
  if (!content) {
    throw new Error("OpenAI-compatible provider returned empty content");
  }

  return content;
}

function cleanPersonaReply(text: string) {
  return text
    .split("\n")
    .map((line) => line.trim())
    .filter((line) => {
      const lower = line.toLowerCase();
      if (!lower) return false;
      return ![
        "as an ai",
        "i'm an ai",
        "i am an ai",
        "i'm a model",
        "i am a model",
        "i'm sorry",
        "i’m sorry",
        "i can't",
        "i cannot",
        "i won't",
        "i will not",
        "as a language model",
        "i don't roleplay",
        "i do not roleplay",
        "i cannot discuss",
        "i can't discuss",
      ].some((prefix) => lower.startsWith(prefix));
    })
    .join(" ")
    .replace(/\s+/g, " ")
    .trim();
}

export async function generatePersonaReplyWithProviders(
  params: ProviderGenerationParams,
): Promise<ProviderGenerationResult> {
  const {
    persona,
    system,
    styleGuide,
    conversation,
    userMessage,
    openaiApiKey,
    openaiBaseUrl,
    openaiModel,
    anthropicApiKey,
    anthropicBaseUrl,
    anthropicModels,
    selectedContextIds,
    relevantNewsIds,
    requestId,
  } = params;

  let content = "";
  const providerErrors: string[] = [];
  let lastError: Error | null = null;
  let usedProvider: "openai_compatible" | "anthropic" | null = null;
  let usedOpenAIModel: string | null = null;
  let usedAnthropicModel: string | null = null;
  let attemptedOpenAI = false;

  if (openaiApiKey) {
    for (
      let attempt = 1;
      attempt <= MAX_GENERATION_RETRIES && !content;
      attempt += 1
    ) {
      attemptedOpenAI = true;
      const metric = createProviderMetricContext(
        "generate-message",
        "persona_reply",
        "openai_compatible",
        {
          requestId,
          personaId: persona.personaId,
          attempt,
          model: openaiModel,
          selectedContextIds,
          relevantNewsIds,
        },
      );
      try {
        const candidate = cleanPersonaReply(
          await generateWithOpenAICompatible(
            openaiApiKey,
            openaiBaseUrl,
            openaiModel,
            persona,
            system,
            styleGuide,
            conversation,
            userMessage,
          ),
        );
        if (candidate) {
          content = candidate;
          usedProvider = "openai_compatible";
          usedOpenAIModel = openaiModel;
          logProviderMetricSuccess(metric);
          logEdgeEvent("generate-message", "openai_success", {
            requestId,
            personaId: persona.personaId,
            attempt,
            model: openaiModel,
            selectedContextIds,
            relevantNewsIds,
          });
          break;
        }

        lastError = new Error("Persona reply empty after cleanup");
        logProviderMetricFailure(metric, lastError);
        providerErrors.push(
          `[${openaiModel} attempt ${attempt}] openai_compatible: Provider returned empty content after cleanup`,
        );
      } catch (error) {
        lastError = error instanceof Error ? error : new Error(String(error));
        logProviderMetricFailure(metric, lastError);
        providerErrors.push(
          `[${openaiModel} attempt ${attempt}] openai_compatible: ${lastError.message}`,
        );
        logEdgeEvent("generate-message", "openai_failure", {
          requestId,
          personaId: persona.personaId,
          attempt,
          model: openaiModel,
          error: lastError.message,
        });
      }

      if (!content && attempt < MAX_GENERATION_RETRIES) {
        await delay(200 * attempt);
      }
    }
  } else {
    providerErrors.push("[config] openai_compatible: OPENAI_API_KEY missing");
    logProviderMetricSkipped(
      "generate-message",
      "persona_reply",
      "openai_compatible",
      {
        requestId,
        personaId: persona.personaId,
        reason: "missing_api_key",
        selectedContextIds,
        relevantNewsIds,
      },
    );
  }

  if (!content) {
    if (!anthropicApiKey) {
      providerErrors.push("[config] anthropic: ANTHROPIC_API_KEY missing");
      logProviderMetricSkipped(
        "generate-message",
        "persona_reply",
        "anthropic",
        {
          requestId,
          personaId: persona.personaId,
          reason: "missing_api_key",
          selectedContextIds,
          relevantNewsIds,
        },
      );
      logEdgeEvent("generate-message", "anthropic_missing_config", {
        requestId,
        personaId: persona.personaId,
        selectedContextIds,
        relevantNewsIds,
      });
    } else {
      if (attemptedOpenAI) {
        logProviderMetricFallback(
          "generate-message",
          "persona_reply",
          "openai_compatible",
          "anthropic",
          {
            requestId,
            personaId: persona.personaId,
            reason: "openai_unavailable_or_exhausted",
          },
        );
      }
      modelLoop:
      for (const anthropicModel of anthropicModels) {
        for (
          let attempt = 1;
          attempt <= MAX_GENERATION_RETRIES && !content;
          attempt += 1
        ) {
          const metric = createProviderMetricContext(
            "generate-message",
            "persona_reply",
            "anthropic",
            {
              requestId,
              personaId: persona.personaId,
              attempt,
              model: anthropicModel,
              selectedContextIds,
              relevantNewsIds,
            },
          );
          try {
            const candidate = cleanPersonaReply(
              await generateWithAnthropic(
                anthropicApiKey,
                anthropicBaseUrl,
                anthropicModel,
                persona,
                system,
                styleGuide,
                conversation,
                userMessage,
              ),
            );
            if (candidate) {
              content = candidate;
              usedProvider = "anthropic";
              usedAnthropicModel = anthropicModel;
              logProviderMetricSuccess(metric);
              logEdgeEvent("generate-message", "anthropic_success", {
                requestId,
                personaId: persona.personaId,
                attempt,
                model: anthropicModel,
                selectedContextIds,
                relevantNewsIds,
              });
              break modelLoop;
            }

            lastError = new Error("Persona reply empty after cleanup");
            logProviderMetricFailure(metric, lastError);
            providerErrors.push(
              `[${anthropicModel} attempt ${attempt}] anthropic: Provider returned empty content after cleanup`,
            );
          } catch (error) {
            lastError = error instanceof Error
              ? error
              : new Error(String(error));
            logProviderMetricFailure(metric, lastError);
            providerErrors.push(
              `[${anthropicModel} attempt ${attempt}] anthropic: ${lastError.message}`,
            );
            logEdgeEvent("generate-message", "anthropic_failure", {
              requestId,
              personaId: persona.personaId,
              attempt,
              model: anthropicModel,
              error: lastError.message,
            });

            if (isTerminalAnthropicError(lastError)) {
              break modelLoop;
            }
          }

          if (!content && attempt < MAX_GENERATION_RETRIES) {
            await delay(200 * attempt);
          }
        }
      }
    }
  }

  return {
    content: content || null,
    providerErrors,
    lastError,
    usedProvider,
    usedOpenAIModel,
    usedAnthropicModel,
  };
}
