function trimmedString(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : null;
}

function statusCode(value: unknown): number | null {
  if (typeof value === "number" && Number.isFinite(value)) {
    return value;
  }

  const trimmed = trimmedString(value);
  if (!trimmed) return null;

  const parsed = Number(trimmed);
  return Number.isFinite(parsed) ? parsed : null;
}

function parseStructuredContainer(value: unknown): Record<string, unknown> | unknown[] | null {
  const trimmed = trimmedString(value);
  if (!trimmed) return null;

  const startsLikeJsonObject = trimmed.startsWith("{") && trimmed.endsWith("}");
  const startsLikeJsonArray = trimmed.startsWith("[") && trimmed.endsWith("]");
  if (!startsLikeJsonObject && !startsLikeJsonArray) {
    return null;
  }

  try {
    const parsed = JSON.parse(trimmed);
    if (parsed && typeof parsed === "object") {
      return parsed as Record<string, unknown> | unknown[];
    }
  } catch {
    return null;
  }

  return null;
}

function shouldTreatValueAsText(record: Record<string, unknown>) {
  const type = trimmedString(record.type);
  if (type && ["text", "output_text", "input_text"].includes(type)) {
    return true;
  }

  const keys = Object.keys(record);
  return keys.length > 0 &&
    keys.every((key) =>
      ["value", "type", "annotations", "index"].includes(key)
    );
}

function appendText(
  value: unknown,
  output: string[],
  seen: Set<string>,
) {
  const trimmed = trimmedString(value);
  if (!trimmed || seen.has(trimmed)) return;
  seen.add(trimmed);
  output.push(trimmed);
}

function collectKnownText(
  value: unknown,
  output: string[],
  seen: Set<string>,
) {
  if (value == null) return;

  const parsedContainer = parseStructuredContainer(value);
  if (parsedContainer) {
    collectKnownText(parsedContainer, output, seen);
    return;
  }

  if (typeof value === "string") {
    appendText(value, output, seen);
    return;
  }

  if (Array.isArray(value)) {
    for (const item of value) {
      collectKnownText(item, output, seen);
    }
    return;
  }

  if (typeof value !== "object") return;

  const record = value as Record<string, unknown>;

  appendText(record.output_text, output, seen);
  appendText(record.text, output, seen);
  appendText(record.content, output, seen);

  if (shouldTreatValueAsText(record)) {
    appendText(record.value, output, seen);
  }

  for (
    const key of [
      "output",
      "choices",
      "message",
      "content",
      "delta",
      "text",
      "parts",
      "messages",
      "items",
      "body",
      "data",
      "result",
      "results",
      "response",
    ]
  ) {
    const nested = record[key];
    if (nested == null) continue;
    collectKnownText(nested, output, seen);
  }
}

function shapeOf(value: unknown): string {
  if (value == null) return "null";
  if (Array.isArray(value)) return "array";
  return typeof value;
}

function limitedKeys(value: unknown): string[] {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    return [];
  }

  return Object.keys(value as Record<string, unknown>).slice(0, 8);
}

function previewValue(value: unknown, maxLength = 240): string | null {
  if (value == null) return null;

  if (typeof value === "string") {
    return value.slice(0, maxLength);
  }

  try {
    return JSON.stringify(value).slice(0, maxLength);
  } catch {
    return String(value).slice(0, maxLength);
  }
}

function firstObject(value: unknown): Record<string, unknown> | null {
  if (!Array.isArray(value) || value.length === 0) return null;
  const first = value[0];
  if (!first || typeof first !== "object" || Array.isArray(first)) {
    return null;
  }
  return first as Record<string, unknown>;
}

export function extractOpenAICompatibleContent(payload: unknown): string {
  const output: string[] = [];
  const seen = new Set<string>();
  collectKnownText(payload, output, seen);
  return output.join("\n").trim();
}

export function extractOpenAICompatibleError(payload: unknown): string | null {
  if (!payload || typeof payload !== "object" || Array.isArray(payload)) {
    return null;
  }

  const record = payload as Record<string, unknown>;
  const errorRecord = record.error &&
      typeof record.error === "object" &&
      !Array.isArray(record.error)
    ? record.error as Record<string, unknown>
    : null;
  const status = statusCode(record.status);
  const message = trimmedString(record.msg) ??
    trimmedString(record.message) ??
    trimmedString(record.error) ??
    trimmedString(errorRecord?.message);

  if (status !== null && status >= 400) {
    return message
      ? `OpenAI-compatible provider returned status ${status}: ${message}`
      : `OpenAI-compatible provider returned status ${status}`;
  }

  if (errorRecord) {
    const errorType = trimmedString(errorRecord.type);
    if (message || errorType) {
      return [errorType, message].filter(Boolean).join(": ");
    }
  }

  return null;
}

export function isTerminalOpenAICompatibleError(error: unknown) {
  const message = error instanceof Error ? error.message : String(error);
  const normalized = message.toLowerCase();

  return [
    "api token has expired",
    "rate limit",
    "too many requests",
    "exceeded your current rate limit",
    "invalid api key",
    "incorrect api key",
    "authentication",
    "unauthorized",
    "forbidden",
    "returned status 429",
    "returned status 449",
    "returned status 401",
    "returned status 403",
    "returned status 439",
  ].some((pattern) => normalized.includes(pattern));
}

export function formatOpenAICompatiblePayloadSummary(payload: unknown): string {
  if (!payload || typeof payload !== "object" || Array.isArray(payload)) {
    return JSON.stringify({ payloadShape: shapeOf(payload) });
  }

  const record = payload as Record<string, unknown>;
  const parsedBody = parseStructuredContainer(record.body) ?? record.body;
  const parsedResult = parseStructuredContainer(record.result) ?? record.result;
  const firstChoice = firstObject(record.choices);
  const firstMessage = firstChoice &&
      typeof firstChoice.message === "object" &&
      firstChoice.message !== null &&
      !Array.isArray(firstChoice.message)
    ? firstChoice.message as Record<string, unknown>
    : null;
  const firstOutput = firstObject(record.output);
  const firstOutputContent = firstOutput ? firstObject(firstOutput.content) : null;

  return JSON.stringify({
    topLevelKeys: limitedKeys(record),
    statusPreview: previewValue(record.status, 80),
    msgPreview: previewValue(record.msg, 160),
    bodyShape: shapeOf(parsedBody),
    bodyKeys: limitedKeys(parsedBody),
    bodyPreview: previewValue(record.body),
    resultShape: shapeOf(parsedResult),
    resultKeys: limitedKeys(parsedResult),
    outputTextShape: shapeOf(record.output_text),
    outputShape: shapeOf(record.output),
    choicesShape: shapeOf(record.choices),
    firstChoiceKeys: limitedKeys(firstChoice),
    firstMessageKeys: limitedKeys(firstMessage),
    firstMessageContentShape: firstMessage ? shapeOf(firstMessage.content) : "null",
    firstOutputKeys: limitedKeys(firstOutput),
    firstOutputContentKeys: limitedKeys(firstOutputContent),
    extractedLength: extractOpenAICompatibleContent(payload).length,
  });
}
