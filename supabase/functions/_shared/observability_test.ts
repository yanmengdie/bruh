import {
  createObservationContext,
  EDGE_REQUEST_ID_HEADER,
  observationDurationMs,
  responseHeadersWithRequestId,
} from "./observability.ts";

Deno.test("responseHeadersWithRequestId preserves headers and exposes request id", () => {
  const headers = responseHeadersWithRequestId(
    {
      "Cache-Control": "no-store",
      "Access-Control-Expose-Headers": "etag",
    },
    "req-123",
  );

  if (headers[EDGE_REQUEST_ID_HEADER] !== "req-123") {
    throw new Error("expected request id header to be attached");
  }

  if (headers["Cache-Control"] !== "no-store") {
    throw new Error("expected base headers to be preserved");
  }

  const exposed = headers["Access-Control-Expose-Headers"] ?? "";
  if (!exposed.toLowerCase().includes("etag")) {
    throw new Error("expected existing exposed header to be preserved");
  }
  if (!exposed.toLowerCase().includes(EDGE_REQUEST_ID_HEADER)) {
    throw new Error("expected request id header to be exposed");
  }
});

Deno.test("observationDurationMs uses explicit timestamps", () => {
  const context = createObservationContext("feed", "req-1", 100);
  const duration = observationDurationMs(context, 175);

  if (duration !== 75) {
    throw new Error(`expected duration 75, got ${duration}`);
  }
});
