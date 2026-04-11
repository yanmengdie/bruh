import { logEdgeError, logEdgeEvent } from "./observability.ts";

export type ProviderMetricContext<
  TDetails extends Record<string, unknown> = Record<string, unknown>,
> = {
  scope: string;
  operation: string;
  provider: string;
  startedAt: number;
  details: TDetails;
};

export function createProviderMetricContext<
  TDetails extends Record<string, unknown> = Record<string, unknown>,
>(
  scope: string,
  operation: string,
  provider: string,
  details: TDetails = {} as TDetails,
  startedAt = Date.now(),
): ProviderMetricContext<TDetails> {
  return {
    scope,
    operation,
    provider,
    startedAt,
    details,
  };
}

export function providerMetricPayload<
  TContextDetails extends Record<string, unknown>,
  TDetails extends Record<string, unknown> = Record<string, unknown>,
>(
  context: ProviderMetricContext<TContextDetails>,
  outcome: "success" | "failure" | "fallback" | "skipped",
  details: TDetails = {} as TDetails,
  now = Date.now(),
):
  & {
    operation: string;
    provider: string;
    outcome: "success" | "failure" | "fallback" | "skipped";
    durationMs: number;
  }
  & TContextDetails
  & TDetails {
  return {
    operation: context.operation,
    provider: context.provider,
    outcome,
    durationMs: Math.max(0, now - context.startedAt),
    ...context.details,
    ...details,
  };
}

export function logProviderMetricSuccess(
  context: ProviderMetricContext,
  details: Record<string, unknown> = {},
) {
  logEdgeEvent(
    context.scope,
    "provider_metric",
    providerMetricPayload(context, "success", details),
  );
}

export function logProviderMetricFailure(
  context: ProviderMetricContext,
  error: unknown,
  details: Record<string, unknown> = {},
) {
  logEdgeError(
    context.scope,
    "provider_metric",
    error,
    providerMetricPayload(context, "failure", details),
  );
}

export function logProviderMetricFallback(
  scope: string,
  operation: string,
  fromProvider: string,
  toProvider: string,
  details: Record<string, unknown> = {},
) {
  logEdgeEvent(scope, "provider_metric", {
    operation,
    provider: fromProvider,
    outcome: "fallback",
    fallbackProvider: toProvider,
    ...details,
  });
}

export function logProviderMetricSkipped(
  scope: string,
  operation: string,
  provider: string,
  details: Record<string, unknown> = {},
) {
  logEdgeEvent(scope, "provider_metric", {
    operation,
    provider,
    outcome: "skipped",
    ...details,
  });
}
