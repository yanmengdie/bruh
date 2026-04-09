const FALLBACK_ANTHROPIC_MODELS = [
  "claude-sonnet-4-20250514",
  "claude-sonnet-4-0",
  "claude-3-7-sonnet-20250219",
  "claude-3-5-sonnet-20241022",
]

export function anthropicModelCandidates(configuredModel: string | null | undefined) {
  const primaryModel = typeof configuredModel === "string" ? configuredModel.trim() : ""

  return [...new Set(
    [primaryModel, ...FALLBACK_ANTHROPIC_MODELS]
      .map((model) => model.trim())
      .filter((model) => model.length > 0),
  )]
}

export function isUnsupportedAnthropicModelError(error: unknown) {
  const message = error instanceof Error ? error.message : String(error)
  const normalized = message.toLowerCase()

  return [
    "requested model is not supported",
    "model is not supported",
    "unsupported model",
    "model_not_found",
    "invalid model",
    "unknown model",
  ].some((pattern) => normalized.includes(pattern))
}

export function isTerminalAnthropicError(error: unknown) {
  if (isUnsupportedAnthropicModelError(error)) return true

  const message = error instanceof Error ? error.message : String(error)
  const normalized = message.toLowerCase()

  return [
    "authentication_error",
    "invalid x-api-key",
    "correct claude code client",
    "some parameters in your request appear to be incorrect",
    "请求携带的一些参数似乎不正确",
  ].some((pattern) => normalized.includes(pattern))
}
