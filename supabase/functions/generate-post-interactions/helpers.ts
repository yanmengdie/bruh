import { logEdgeEvent } from "../_shared/observability.ts";

export function asString(value: unknown): string {
  return typeof value === "string" ? value.trim() : "";
}

export function normalizeBoolean(value: unknown, fallback = false): boolean {
  if (typeof value === "boolean") return value;
  if (typeof value === "string") {
    const normalized = value.trim().toLowerCase();
    if (["true", "1", "yes"].includes(normalized)) return true;
    if (["false", "0", "no"].includes(normalized)) return false;
  }
  return fallback;
}

export function logGenerationEvent(
  event: string,
  details: Record<string, unknown>,
) {
  logEdgeEvent("generate-post-interactions", event, details);
}

export async function delay(ms: number) {
  await new Promise((resolve) => setTimeout(resolve, ms));
}
