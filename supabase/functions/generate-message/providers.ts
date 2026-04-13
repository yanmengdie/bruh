import {
  extractOpenAICompatibleError,
  extractOpenAICompatibleContent,
  formatOpenAICompatiblePayloadSummary,
  isTerminalOpenAICompatibleError,
} from "../_shared/openai_compatible.ts";
import { logEdgeEvent } from "../_shared/observability.ts";
import {
  createProviderMetricContext,
  logProviderMetricFailure,
  logProviderMetricSkipped,
  logProviderMetricSuccess,
} from "../_shared/provider_metrics.ts";
import type { PersonaDefinition } from "../_shared/personas.ts";
import { delay } from "./helpers.ts";
import { buildProviderMessages } from "./prompting.ts";
import type { ConversationTurn } from "./types.ts";

const MAX_GENERATION_RETRIES = 3;

export type ProviderGenerationResult = {
  content: string | null;
  providerErrors: string[];
  lastError: Error | null;
  usedProvider: "openai_compatible" | null;
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
  selectedContextIds: string[];
  relevantNewsIds: string[];
  requestId?: string;
};

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
  const providerMessages = buildProviderMessages(
    persona,
    styleGuide,
    conversation,
    userMessage,
  );
  let responsesError: string | null = null;

  const responsesRequest = await fetch(`${baseUrl}/responses`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${apiKey}`,
    },
    body: JSON.stringify({
      model,
      instructions: system,
      input: providerMessages.map((message) => ({
        role: message.role,
        content: [{ type: "input_text", text: message.content }],
      })),
      max_output_tokens: 120,
      temperature: 0.85,
    }),
  });

  if (responsesRequest.ok) {
    const payload = await responsesRequest.json();
    const providerError = extractOpenAICompatibleError(payload);
    if (providerError) {
      throw new Error(providerError);
    }
    const content = extractOpenAICompatibleContent(payload);
    if (content) {
      return content;
    }
    responsesError =
      `responses empty: ${formatOpenAICompatiblePayloadSummary(payload)}`;
  } else {
    responsesError = `responses failed: ${await responsesRequest.text()}`;
  }

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
        ...providerMessages,
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
  const providerError = extractOpenAICompatibleError(payload);
  if (providerError) {
    throw new Error(providerError);
  }
  const content = extractOpenAICompatibleContent(payload);
  if (!content) {
    const summary = formatOpenAICompatiblePayloadSummary(payload);
    throw new Error(
      `OpenAI-compatible provider returned empty content. chat=${summary}${
        responsesError ? `; ${responsesError}` : ""
      }`,
    );
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
    selectedContextIds,
    relevantNewsIds,
    requestId,
  } = params;

  let content = "";
  const providerErrors: string[] = [];
  let lastError: Error | null = null;
  let usedProvider: "openai_compatible" | null = null;
  let usedOpenAIModel: string | null = null;
  let usedAnthropicModel: string | null = null;

  if (openaiApiKey) {
    for (
      let attempt = 1;
      attempt <= MAX_GENERATION_RETRIES && !content;
      attempt += 1
    ) {
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
        if (isTerminalOpenAICompatibleError(lastError)) {
          break;
        }
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

  return {
    content: content || null,
    providerErrors,
    lastError,
    usedProvider,
    usedOpenAIModel,
    usedAnthropicModel,
  };
}
