export type APIContractName =
  | "feed.v1"
  | "generate-message.v1"
  | "message-starters.v1"
  | "generate-post-interactions.v1"

export const API_CLIENT_VERSION_HEADER = "x-bruh-client-version"
export const API_ACCEPT_CONTRACT_HEADER = "x-bruh-accept-contract"
export const API_SERVER_VERSION_HEADER = "x-bruh-server-version"
export const API_CONTRACT_HEADER = "x-bruh-contract"
export const API_COMPAT_MODE_HEADER = "x-bruh-compat-mode"

export const CURRENT_API_VERSION = "2026-04-12"
export const CURRENT_COMPAT_MODE = "additive"

type HeaderRecord = Record<string, string>

function toHeaderRecord(headers: HeadersInit | undefined): HeaderRecord {
  if (!headers) return {}

  if (headers instanceof Headers) {
    return Object.fromEntries(headers.entries())
  }

  if (Array.isArray(headers)) {
    return Object.fromEntries(headers)
  }

  return { ...headers }
}

function mergeCsvValues(currentValue: string | undefined, nextValues: string[]) {
  const seen = new Set<string>()
  const merged: string[] = []

  for (const value of (currentValue ?? "").split(",")) {
    const normalized = value.trim()
    if (!normalized) continue
    const dedupeKey = normalized.toLowerCase()
    if (!seen.has(dedupeKey)) {
      seen.add(dedupeKey)
      merged.push(normalized)
    }
  }

  for (const value of nextValues) {
    const normalized = value.trim()
    if (!normalized) continue
    const dedupeKey = normalized.toLowerCase()
    if (!seen.has(dedupeKey)) {
      seen.add(dedupeKey)
      merged.push(normalized)
    }
  }

  return merged.join(", ")
}

export function contractHeaders(
  baseHeaders: HeadersInit | undefined,
  contract: APIContractName,
): HeaderRecord {
  const headers = toHeaderRecord(baseHeaders)

  return {
    ...headers,
    "Access-Control-Expose-Headers": mergeCsvValues(headers["Access-Control-Expose-Headers"], [
      API_SERVER_VERSION_HEADER,
      API_CONTRACT_HEADER,
      API_COMPAT_MODE_HEADER,
    ]),
    [API_SERVER_VERSION_HEADER]: CURRENT_API_VERSION,
    [API_CONTRACT_HEADER]: contract,
    [API_COMPAT_MODE_HEADER]: CURRENT_COMPAT_MODE,
  }
}

export function requestedContract(request: Request) {
  return request.headers.get(API_ACCEPT_CONTRACT_HEADER)?.trim().toLowerCase() ?? ""
}

export function requestedClientVersion(request: Request) {
  return request.headers.get(API_CLIENT_VERSION_HEADER)?.trim() || null
}

export function isAcceptedContractCompatible(request: Request, contract: APIContractName) {
  const accepted = requestedContract(request)
  return accepted.length === 0 || accepted === "*" || accepted === contract
}
