export type EdgeErrorCategory =
  | "validation"
  | "config"
  | "database"
  | "provider"
  | "network"
  | "timeout"
  | "auth"
  | "unknown";

export const EDGE_REQUEST_ID_HEADER = "x-bruh-request-id";

type HeaderRecord = Record<string, string>;

export type EdgeObservationContext = {
  scope: string;
  requestId: string;
  startedAt: number;
};

function toHeaderRecord(headers: HeadersInit | undefined): HeaderRecord {
  if (!headers) return {};

  if (headers instanceof Headers) {
    return Object.fromEntries(headers.entries());
  }

  if (Array.isArray(headers)) {
    return Object.fromEntries(headers);
  }

  return { ...headers };
}

function mergeCsvValues(
  currentValue: string | undefined,
  nextValues: string[],
) {
  const seen = new Set<string>();
  const merged: string[] = [];

  for (const value of (currentValue ?? "").split(",")) {
    const normalized = value.trim();
    if (!normalized) continue;
    const dedupeKey = normalized.toLowerCase();
    if (!seen.has(dedupeKey)) {
      seen.add(dedupeKey);
      merged.push(normalized);
    }
  }

  for (const value of nextValues) {
    const normalized = value.trim();
    if (!normalized) continue;
    const dedupeKey = normalized.toLowerCase();
    if (!seen.has(dedupeKey)) {
      seen.add(dedupeKey);
      merged.push(normalized);
    }
  }

  return merged.join(", ");
}

export function errorMessage(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}

export function classifyError(error: unknown): EdgeErrorCategory {
  const message = errorMessage(error).toLowerCase();

  if (
    message.includes("required") ||
    message.includes("invalid ") ||
    message.includes("unknown personaid") ||
    message.includes("method not allowed")
  ) {
    return "validation";
  }

  if (
    message.includes("missing environment") ||
    message.includes("api key missing") ||
    message.includes("missing supabase")
  ) {
    return "config";
  }

  if (
    message.includes("signal timed out") ||
    message.includes("timed out") ||
    message.includes("timeout") ||
    message.includes("aborted")
  ) {
    return "timeout";
  }

  if (
    message.includes("authentication") ||
    message.includes("invalid x-api-key") ||
    message.includes("unauthorized") ||
    message.includes("forbidden")
  ) {
    return "auth";
  }

  if (
    message.includes("openai") ||
    message.includes("anthropic") ||
    message.includes("nano banana") ||
    message.includes("tts") ||
    message.includes("provider")
  ) {
    return "provider";
  }

  if (
    message.includes("fetch failed") ||
    message.includes("network") ||
    message.includes("econn") ||
    message.includes("dns") ||
    message.includes("socket")
  ) {
    return "network";
  }

  if (
    message.includes("supabase") ||
    message.includes("relation ") ||
    message.includes("column ") ||
    message.includes("constraint") ||
    message.includes("feed_items") ||
    message.includes("source_posts") ||
    message.includes("news_events") ||
    message.includes("persona_news_scores")
  ) {
    return "database";
  }

  return "unknown";
}

export function createObservationContext(
  scope: string,
  requestId: string = crypto.randomUUID(),
  startedAt = Date.now(),
): EdgeObservationContext {
  return { scope, requestId, startedAt };
}

export function observationDurationMs(
  context: EdgeObservationContext,
  now = Date.now(),
) {
  return Math.max(0, now - context.startedAt);
}

export function responseHeadersWithRequestId(
  baseHeaders: HeadersInit | undefined,
  requestId: string,
): HeaderRecord {
  const headers = toHeaderRecord(baseHeaders);

  return {
    ...headers,
    "Access-Control-Expose-Headers": mergeCsvValues(
      headers["Access-Control-Expose-Headers"],
      [EDGE_REQUEST_ID_HEADER],
    ),
    [EDGE_REQUEST_ID_HEADER]: requestId,
  };
}

export function logEdgeEvent(
  scope: string,
  event: string,
  details: Record<string, unknown> = {},
) {
  console.log(JSON.stringify({
    scope,
    event,
    ...details,
    loggedAt: new Date().toISOString(),
  }));
}

export function logEdgeError(
  scope: string,
  event: string,
  error: unknown,
  details: Record<string, unknown> = {},
) {
  console.error(JSON.stringify({
    scope,
    event,
    errorCategory: classifyError(error),
    errorMessage: errorMessage(error),
    ...details,
    loggedAt: new Date().toISOString(),
  }));
}

export function logEdgeStart(
  context: EdgeObservationContext,
  event: string,
  details: Record<string, unknown> = {},
) {
  logEdgeEvent(context.scope, event, {
    requestId: context.requestId,
    ...details,
  });
}

export function logEdgeSuccess(
  context: EdgeObservationContext,
  event: string,
  details: Record<string, unknown> = {},
) {
  logEdgeEvent(context.scope, event, {
    requestId: context.requestId,
    durationMs: observationDurationMs(context),
    ...details,
  });
}

export function logEdgeFailure(
  context: EdgeObservationContext,
  event: string,
  error: unknown,
  details: Record<string, unknown> = {},
) {
  logEdgeError(context.scope, event, error, {
    requestId: context.requestId,
    durationMs: observationDurationMs(context),
    ...details,
  });
}
