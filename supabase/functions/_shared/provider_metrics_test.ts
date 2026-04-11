import {
  createProviderMetricContext,
  providerMetricPayload,
} from "./provider_metrics.ts";

Deno.test("providerMetricPayload includes duration and provider details", () => {
  const context = createProviderMetricContext(
    "generate-message",
    "persona_reply",
    "openai_compatible",
    { requestId: "req-1", attempt: 2 },
    100,
  );

  const payload = providerMetricPayload(
    context,
    "success",
    { model: "gpt-4.1-mini" },
    175,
  );

  if (payload.durationMs !== 75) {
    throw new Error(`expected duration 75, got ${payload.durationMs}`);
  }

  if (payload.provider !== "openai_compatible") {
    throw new Error("expected provider to be preserved");
  }

  if (payload.operation !== "persona_reply") {
    throw new Error("expected operation to be preserved");
  }

  if (payload.model !== "gpt-4.1-mini") {
    throw new Error("expected model detail to be merged");
  }
});
