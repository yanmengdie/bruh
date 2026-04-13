import { createClient } from "jsr:@supabase/supabase-js@2";
import {
  contractHeaders,
  isAcceptedContractCompatible,
  requestedClientVersion,
} from "../_shared/api_contract.ts";
import { corsHeaders } from "../_shared/cors.ts";
import {
  getOptionalScopedEnv,
  getScopedEnvOrDefault,
  resolveSupabaseServiceConfig,
} from "../_shared/environment.ts";
import {
  classifyError,
  createObservationContext,
  logEdgeFailure,
  logEdgeStart,
  logEdgeSuccess,
  responseHeadersWithRequestId,
} from "../_shared/observability.ts";
import { handlePersistentRequest, handleStatelessRequest } from "./handlers.ts";
import { asString, normalizeBoolean } from "./helpers.ts";
import {
  normalizeTransientComments,
  normalizeTransientLikes,
} from "./storage.ts";
import type { InteractionRequestPayload } from "./handlers.ts";

Deno.serve(async (request) => {
  const baseResponseHeaders = contractHeaders(
    corsHeaders,
    "generate-post-interactions.v1",
  );
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: baseResponseHeaders });
  }

  const observation = createObservationContext("generate-post-interactions");
  const responseHeaders = responseHeadersWithRequestId(
    baseResponseHeaders,
    observation.requestId,
  );
  const clientVersion = requestedClientVersion(request);
  logEdgeStart(observation, "request_started", {
    method: request.method,
    clientVersion,
  });

  const respond = (
    body: unknown,
    init: ResponseInit = {},
    details: Record<string, unknown> = {},
  ) => {
    const status = init.status ?? 200;

    if (status >= 500) {
      const responseError = body && typeof body === "object"
        ? asString((body as Record<string, unknown>).error)
        : "";
      logEdgeFailure(
        observation,
        "request_failed",
        responseError || "Unhandled request failure",
        {
          status,
          clientVersion,
          ...details,
        },
      );
    } else if (status >= 400) {
      logEdgeSuccess(observation, "request_rejected", {
        status,
        clientVersion,
        ...details,
      });
    } else {
      logEdgeSuccess(observation, "request_succeeded", {
        status,
        clientVersion,
        ...details,
      });
    }

    return Response.json(body, {
      ...init,
      headers: {
        ...responseHeaders,
        ...(init.headers
          ? Object.fromEntries(new Headers(init.headers).entries())
          : {}),
      },
    });
  };

  try {
    if (
      !isAcceptedContractCompatible(request, "generate-post-interactions.v1")
    ) {
      return respond(
        {
          error:
            "Requested contract is incompatible with generate-post-interactions.v1",
          errorCategory: "validation",
        },
        { status: 412 },
      );
    }

    if (request.method !== "POST") {
      return respond({
        error: "Method not allowed",
        errorCategory: "validation",
      }, { status: 405 });
    }

    const { projectUrl, serviceRoleKey } = resolveSupabaseServiceConfig();
    const openaiApiKey = getOptionalScopedEnv("OPENAI_API_KEY");
    const openaiBaseUrl = getScopedEnvOrDefault(
      "OPENAI_BASE_URL",
      "https://api.codexzh.com/v1",
    ).replace(/\/$/, "");
    const openaiModel = getScopedEnvOrDefault("OPENAI_MODEL", "gpt-5.2");

    const body = await request.json().catch(() => ({})) as Record<
      string,
      unknown
    >;
    const postId = asString(body.postId);
    const personaId = asString(body.personaId);
    const postContent = asString(body.postContent);
    const topic = asString(body.topic);
    const viewerComment = asString(body.viewerComment);
    const viewerCommentId = asString(body.viewerCommentId) ||
      `viewer-${crypto.randomUUID()}`;
    const viewerLikeAction = asString(body.viewerLikeAction);
    const replyToCommentId = asString(body.replyToCommentId) || null;
    const replyTargetAuthorId = asString(body.replyTargetAuthorId) || personaId;
    const persistRemote = normalizeBoolean(body.persistRemote, true);
    const transientLikes = normalizeTransientLikes(body.existingLikes, postId);
    const transientComments = normalizeTransientComments(
      body.existingComments,
      postId,
    );

    if (!postId || !personaId || !postContent) {
      return respond(
        {
          error: "postId, personaId and postContent are required",
          errorCategory: "validation",
        },
        { status: 400 },
      );
    }

    const payload: InteractionRequestPayload = {
      postId,
      personaId,
      postContent,
      topic,
      viewerComment,
      viewerCommentId,
      viewerLikeAction,
      replyToCommentId,
      replyTargetAuthorId,
      transientLikes,
      transientComments,
    };

    if (!persistRemote) {
      const result = await handleStatelessRequest(
        {
          openaiApiKey: openaiApiKey ?? undefined,
          openaiBaseUrl,
          openaiModel,
        },
        payload,
      );
      return respond(result.body, { status: result.status });
    }

    const supabase = createClient(projectUrl, serviceRoleKey);
    const result = await handlePersistentRequest(
      supabase,
      {
        openaiApiKey: openaiApiKey ?? undefined,
        openaiBaseUrl,
        openaiModel,
      },
      payload,
    );
    return respond(result.body, { status: result.status });
  } catch (error) {
    const errorCategory = classifyError(error);
    return respond(
      {
        error: error instanceof Error ? error.message : "Unknown error",
        errorCategory,
      },
      { status: 500 },
    );
  }
});
