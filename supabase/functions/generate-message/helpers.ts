export function asString(value: unknown): string {
  return typeof value === "string" ? value.trim() : ""
}

export function countRegexMatches(text: string, pattern: RegExp) {
  return text.match(pattern)?.length ?? 0
}

export function countSignalHits(lower: string, signals: string[]) {
  return signals.reduce((count, signal) => count + (lower.includes(signal) ? 1 : 0), 0)
}

export function approximateSpeechUnitCount(content: string) {
  const trimmed = content.trim()
  if (!trimmed) return 0

  const cjkCharacterCount = countRegexMatches(trimmed, /[\u3400-\u9fff]/gu)
  const nonCJKWordCount = trimmed
    .replace(/[\u3400-\u9fff]/gu, " ")
    .split(/\s+/)
    .filter((word) => word.length > 0)
    .length

  if (cjkCharacterCount === 0) {
    return nonCJKWordCount
  }

  return Math.ceil(cjkCharacterCount / 2) + nonCJKWordCount
}

export function clamp(value: number, min: number, max: number) {
  return Math.min(max, Math.max(min, value))
}

function hashString(value: string) {
  let hash = 2166136261

  for (let index = 0; index < value.length; index += 1) {
    hash ^= value.charCodeAt(index)
    hash = Math.imul(hash, 16777619)
  }

  return hash >>> 0
}

export function seededUnitInterval(seed: string) {
  return hashString(seed) / 4294967295
}

export async function delay(ms: number) {
  await new Promise((resolve) => setTimeout(resolve, ms))
}

export function normalizeBoolean(value: unknown) {
  if (typeof value === "boolean") return value
  if (typeof value === "string") {
    const normalized = value.trim().toLowerCase()
    return normalized === "true" || normalized === "1" || normalized === "yes"
  }
  return false
}
