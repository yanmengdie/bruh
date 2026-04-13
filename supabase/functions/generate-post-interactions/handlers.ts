import {
  fetchStoredState,
  mapStoredState,
  mapTransientState,
  normalizeStoredComments,
  persistComments,
  persistLikes,
  toStoredCommentRows,
  toStoredLikeRows,
} from "./storage.ts";
import {
  fallbackSeedCommenters,
  pickReplyParticipants,
  pickSeedCommenters,
  rankContacts,
} from "./selection.ts";
import {
  generateInteractionsWithFallback,
  generateThreadReplyWithOpenAICompatible,
} from "./providers.ts";
import type {
  SanitizedInteractionResult,
  StoredCommentRow,
  StoredLikeRow,
} from "./types.ts";

export type InteractionProviderConfig = {
  openaiApiKey?: string;
  openaiBaseUrl: string;
  openaiModel: string;
};

export type InteractionRequestPayload = {
  postId: string;
  personaId: string;
  postContent: string;
  topic: string;
  viewerComment: string;
  viewerCommentId: string;
  viewerLikeAction: string;
  replyToCommentId: string | null;
  replyTargetAuthorId: string;
  transientLikes: StoredLikeRow[];
  transientComments: StoredCommentRow[];
};

export type InteractionHandlerResult = {
  body: unknown;
  status?: number;
};

function configError(message: string): InteractionHandlerResult {
  return {
    body: {
      error: message,
      errorCategory: "config",
    },
    status: 500,
  };
}

function buildAllowedLikes(
  ranked: ReturnType<typeof rankContacts>,
  allowedCommenters: ReturnType<typeof pickSeedCommenters>,
) {
  return ranked
    .filter((contact) =>
      allowedCommenters.some((commenter) => commenter.id === contact.id) ||
      contact.score >= 2
    )
    .slice(0, 4);
}

async function generateSeedResult(
  providers: InteractionProviderConfig,
  payload: Pick<
    InteractionRequestPayload,
    "personaId" | "postId" | "postContent" | "topic"
  >,
  allowedLikes: ReturnType<typeof buildAllowedLikes>,
  allowedCommenters: ReturnType<typeof pickSeedCommenters>,
): Promise<SanitizedInteractionResult | null> {
  if (!providers.openaiApiKey) {
    return null;
  }

  return await generateInteractionsWithFallback(
    providers.openaiApiKey,
    providers.openaiBaseUrl,
    providers.openaiModel,
    payload.personaId,
    payload.postId,
    payload.postContent,
    payload.topic,
    [],
    "",
    allowedLikes,
    allowedCommenters,
  );
}

async function generateReplyResult(
  providers: InteractionProviderConfig,
  payload: Pick<
    InteractionRequestPayload,
    "personaId" | "postId" | "postContent" | "topic" | "viewerComment"
  >,
  existingComments: StoredCommentRow[],
  allowedCommenters: ReturnType<typeof pickReplyParticipants>,
): Promise<SanitizedInteractionResult | null> {
  const normalizedExistingComments = normalizeStoredComments(existingComments);
  if (!providers.openaiApiKey) {
    return null;
  }

  return await generateInteractionsWithFallback(
    providers.openaiApiKey,
    providers.openaiBaseUrl,
    providers.openaiModel,
    payload.personaId,
    payload.postId,
    payload.postContent,
    payload.topic,
    normalizedExistingComments,
    payload.viewerComment,
    [],
    allowedCommenters,
  );
}

export async function handleStatelessRequest(
  providers: Pick<
    InteractionProviderConfig,
    "openaiApiKey" | "openaiBaseUrl" | "openaiModel"
  >,
  payload: InteractionRequestPayload,
): Promise<InteractionHandlerResult> {
  let workingLikes = payload.transientLikes;
  let workingComments = payload.transientComments;

  if (!payload.viewerComment) {
    if (workingLikes.length > 0 || workingComments.length > 0) {
      return {
        body: mapTransientState(payload.postId, workingLikes, workingComments),
      };
    }

    const ranked = rankContacts(
      payload.personaId,
      payload.postContent,
      payload.topic,
      [],
      "",
    );
    let allowedCommenters = pickSeedCommenters(ranked);
    if (allowedCommenters.length === 0) {
      allowedCommenters = fallbackSeedCommenters(payload.personaId);
    }
    let allowedLikes = buildAllowedLikes(ranked, allowedCommenters);
    if (allowedLikes.length === 0) {
      allowedLikes = allowedCommenters.slice(0, 2);
    }

    if (allowedCommenters.length === 0 && allowedLikes.length === 0) {
      return {
        body: mapTransientState(payload.postId, workingLikes, workingComments),
      };
    }

    if (!providers.openaiApiKey) {
      return configError("OPENAI_API_KEY is required for stateless generation");
    }

    const generated = await generateInteractionsWithFallback(
      providers.openaiApiKey,
      providers.openaiBaseUrl,
      providers.openaiModel,
      payload.personaId,
      payload.postId,
      payload.postContent,
      payload.topic,
      [],
      "",
      allowedLikes,
      allowedCommenters,
    );

    workingLikes = toStoredLikeRows(generated.likes);
    workingComments = toStoredCommentRows(generated.comments, "seed");
    return {
      body: mapTransientState(payload.postId, workingLikes, workingComments),
    };
  }

  if (
    !workingComments.some((comment) => comment.id === payload.viewerCommentId)
  ) {
    workingComments = [
      ...workingComments,
      {
        id: payload.viewerCommentId,
        post_id: payload.postId,
        author_id: "viewer",
        author_type: "viewer",
        author_display_name: "你",
        content: payload.viewerComment,
        reason_code: "viewer_input",
        in_reply_to_comment_id: payload.replyToCommentId,
        generation_mode: "viewer",
        created_at: new Date().toISOString(),
      },
    ];
  }

  const alreadyReplied = workingComments.some((comment) =>
    comment.in_reply_to_comment_id === payload.viewerCommentId &&
    comment.author_id === payload.replyTargetAuthorId
  );
  if (alreadyReplied) {
    return {
      body: mapTransientState(payload.postId, workingLikes, workingComments),
    };
  }

  if (!providers.openaiApiKey) {
    return configError("OPENAI_API_KEY is required for stateless generation");
  }

  const existingComments = normalizeStoredComments(workingComments);
  const generatedReply = await generateThreadReplyWithOpenAICompatible(
    providers.openaiApiKey,
    providers.openaiBaseUrl,
    providers.openaiModel,
    payload.personaId,
    payload.replyTargetAuthorId,
    payload.postId,
    payload.postContent,
    payload.topic,
    existingComments,
    payload.viewerComment,
    payload.viewerCommentId,
  );

  const mergedComments = [
    ...workingComments,
    ...toStoredCommentRows(generatedReply.comments, "reply"),
  ];
  return {
    body: mapTransientState(payload.postId, workingLikes, mergedComments),
  };
}

export async function handlePersistentRequest(
  supabase: any,
  providers: InteractionProviderConfig,
  payload: InteractionRequestPayload,
): Promise<InteractionHandlerResult> {
  let stored = await fetchStoredState(supabase, payload.postId);

  if (
    payload.viewerLikeAction === "like" || payload.viewerLikeAction === "unlike"
  ) {
    if (payload.viewerLikeAction === "like") {
      await persistLikes(supabase, [{
        id: `like-${payload.postId}-viewer`,
        postId: payload.postId,
        authorId: "viewer",
        authorDisplayName: "你",
        reasonCode: "viewer_like",
        createdAt: new Date().toISOString(),
      }]);
    } else {
      const { error } = await supabase
        .from("feed_likes")
        .delete()
        .eq("post_id", payload.postId)
        .eq("author_id", "viewer");

      if (error) {
        throw new Error(error.message);
      }
    }

    stored = await fetchStoredState(supabase, payload.postId);
    return {
      body: mapStoredState(payload.postId, stored.likes, stored.comments),
    };
  }

  if (!payload.viewerComment) {
    if (stored.likes.length > 0 || stored.comments.length > 0) {
      return {
        body: mapStoredState(payload.postId, stored.likes, stored.comments),
      };
    }

    const ranked = rankContacts(
      payload.personaId,
      payload.postContent,
      payload.topic,
      [],
      "",
    );
    const allowedCommenters = pickSeedCommenters(ranked);
    const allowedLikes = buildAllowedLikes(ranked, allowedCommenters);

    if (allowedCommenters.length === 0 && allowedLikes.length === 0) {
      return {
        body: mapStoredState(payload.postId, stored.likes, stored.comments),
      };
    }

    const generated = await generateSeedResult(
      providers,
      payload,
      allowedLikes,
      allowedCommenters,
    );
    if (!generated) {
      return configError("No valid model provider configured");
    }

    await persistLikes(supabase, generated.likes);
    await persistComments(
      supabase,
      generated.comments.map((item) => ({
        ...item,
        generationMode: "seed" as const,
      })),
    );

    stored = await fetchStoredState(supabase, payload.postId);
    return {
      body: mapStoredState(payload.postId, stored.likes, stored.comments),
    };
  }

  const existingViewer = stored.comments.find((comment) =>
    comment.id === payload.viewerCommentId
  );
  if (!existingViewer) {
    await persistComments(supabase, [{
      id: payload.viewerCommentId,
      postId: payload.postId,
      authorId: "viewer",
      authorDisplayName: "你",
      content: payload.viewerComment,
      reasonCode: "viewer_input",
      inReplyToCommentId: payload.replyToCommentId,
      isViewer: true,
      createdAt: new Date().toISOString(),
      generationMode: "viewer",
    }]);
  }

  stored = await fetchStoredState(supabase, payload.postId);
  const alreadyReplied = stored.comments.some((comment) =>
    comment.in_reply_to_comment_id === payload.viewerCommentId &&
    comment.author_id === payload.personaId
  );
  if (alreadyReplied) {
    return {
      body: mapStoredState(payload.postId, stored.likes, stored.comments),
    };
  }

  const existingComments = normalizeStoredComments(stored.comments);
  const ranked = rankContacts(
    payload.personaId,
    payload.postContent,
    payload.topic,
    existingComments,
    payload.viewerComment,
  );
  const allowedCommenters = pickReplyParticipants(
    payload.personaId,
    ranked,
    payload.viewerComment,
  );

  const replyResult = await generateReplyResult(
    providers,
    payload,
    stored.comments,
    allowedCommenters,
  );
  if (!replyResult) {
    return configError("No valid model provider configured");
  }

  await persistComments(
    supabase,
    replyResult.comments.map((item) => ({
      ...item,
      generationMode: "reply" as const,
    })),
  );

  stored = await fetchStoredState(supabase, payload.postId);
  return {
    body: mapStoredState(payload.postId, stored.likes, stored.comments),
  };
}
