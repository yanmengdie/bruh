import {
  API_ACCEPT_CONTRACT_HEADER,
  API_COMPAT_MODE_HEADER,
  API_CONTRACT_HEADER,
  API_SERVER_VERSION_HEADER,
  contractHeaders,
  isAcceptedContractCompatible,
  requestedClientVersion,
} from "./api_contract.ts"

Deno.test("contractHeaders attaches API metadata and preserves base headers", () => {
  const headers = contractHeaders(
    {
      "Cache-Control": "no-store",
      "Access-Control-Expose-Headers": "etag",
    },
    "feed.v1",
  )

  if (headers["Cache-Control"] !== "no-store") {
    throw new Error("Expected existing cache header to be preserved")
  }

  if (headers[API_CONTRACT_HEADER] !== "feed.v1") {
    throw new Error(`Unexpected contract header: ${headers[API_CONTRACT_HEADER]}`)
  }

  if (!headers[API_SERVER_VERSION_HEADER]) {
    throw new Error("Expected server version header to be populated")
  }

  if (headers[API_COMPAT_MODE_HEADER] !== "additive") {
    throw new Error(`Unexpected compatibility mode: ${headers[API_COMPAT_MODE_HEADER]}`)
  }

  const exposeHeaders = headers["Access-Control-Expose-Headers"] ?? ""
  for (const expected of [API_SERVER_VERSION_HEADER, API_CONTRACT_HEADER, API_COMPAT_MODE_HEADER, "etag"]) {
    if (!exposeHeaders.toLowerCase().includes(expected.toLowerCase())) {
      throw new Error(`Expected expose headers to include ${expected}, got: ${exposeHeaders}`)
    }
  }
})

Deno.test("isAcceptedContractCompatible accepts empty wildcard and exact matches", () => {
  const exact = new Request("https://example.com", {
    headers: { [API_ACCEPT_CONTRACT_HEADER]: "message-starters.v1" },
  })
  const wildcard = new Request("https://example.com", {
    headers: { [API_ACCEPT_CONTRACT_HEADER]: "*" },
  })
  const empty = new Request("https://example.com")
  const mismatch = new Request("https://example.com", {
    headers: { [API_ACCEPT_CONTRACT_HEADER]: "feed.v2" },
  })

  if (!isAcceptedContractCompatible(exact, "message-starters.v1")) {
    throw new Error("Expected exact contract match to be compatible")
  }

  if (!isAcceptedContractCompatible(wildcard, "message-starters.v1")) {
    throw new Error("Expected wildcard contract to be compatible")
  }

  if (!isAcceptedContractCompatible(empty, "message-starters.v1")) {
    throw new Error("Expected empty contract to be treated as legacy compatible")
  }

  if (isAcceptedContractCompatible(mismatch, "message-starters.v1")) {
    throw new Error("Expected mismatched contract to be rejected")
  }
})

Deno.test("requestedClientVersion trims the incoming header", () => {
  const request = new Request("https://example.com", {
    headers: { "x-bruh-client-version": " ios-2026-04-12 " },
  })

  if (requestedClientVersion(request) !== "ios-2026-04-12") {
    throw new Error(`Unexpected client version: ${requestedClientVersion(request)}`)
  }
})
