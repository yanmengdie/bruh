import { isTerminalAnthropicError } from "../_shared/anthropic.ts";
import {
  createProviderMetricContext,
  logProviderMetricFailure,
  logProviderMetricSuccess,
} from "../_shared/provider_metrics.ts";
import { resolvePersonaById } from "../_shared/personas.ts";
import { personaSocialPrompt } from "../_shared/persona_skills.ts";
import {
  cleanGeneratedText,
  safeInteractionFallbackComment,
  sanitizeInteractionText,
} from "./fallbacks.ts";
import { asString, delay, logGenerationEvent } from "./helpers.ts";
import type {
  ExistingComment,
  PersonaProfile,
  RankedContact,
  SanitizedInteractionResult,
  ToolPayload,
} from "./types.ts";

const MAX_GENERATION_RETRIES = 3;

function resolvePersonaProfile(personaId: string): PersonaProfile {
  const resolved = resolvePersonaById(personaId);
  if (resolved) {
    return {
      personaId: resolved.personaId,
      displayName: resolved.displayName,
      stance: resolved.stance,
      domains: resolved.domains,
      triggerKeywords: resolved.triggerKeywords,
    };
  }

  return {
    personaId,
    displayName: personaId,
    stance:
      "grounded, concise, authentic, sounds like the real post author in a social app thread",
    domains: [],
    triggerKeywords: [],
  };
}

function displayNameFor(authorId: string): string {
  if (authorId === "viewer") return "你";
  return resolvePersonaProfile(authorId).displayName;
}

export async function generateTextWithOpenAICompatible(
  apiKey: string,
  baseUrl: string,
  model: string,
  system: string,
  prompt: string,
  metricDetails: Record<string, unknown> = {},
) {
  const metric = createProviderMetricContext(
    "generate-post-interactions",
    "interaction_text",
    "openai_compatible",
    {
      model,
      ...metricDetails,
    },
  );
  const responsesRequest = await fetch(`${baseUrl}/responses`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${apiKey}`,
    },
    body: JSON.stringify({
      model,
      instructions: system,
      input: [{
        role: "user",
        content: [{ type: "input_text", text: prompt }],
      }],
      max_output_tokens: 90,
    }),
  });

  if (responsesRequest.ok) {
    const payload = await responsesRequest.json();
    const content = Array.isArray(payload.output)
      ? payload.output
        .flatMap((item: Record<string, unknown>) =>
          Array.isArray(item.content) ? item.content : []
        )
        .filter((item: Record<string, unknown>) => item.type === "output_text")
        .map((item: Record<string, unknown>) => asString(item.text))
        .join("\n")
        .trim()
      : "";

    if (content) {
      const cleaned = cleanGeneratedText(content);
      if (cleaned) {
        logProviderMetricSuccess(metric, { apiPath: "responses" });
        return cleaned;
      }
    }
  }

  const chatResponse = await fetch(`${baseUrl}/chat/completions`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${apiKey}`,
    },
    body: JSON.stringify({
      model,
      messages: [
        { role: "system", content: system },
        { role: "user", content: prompt },
      ],
      max_tokens: 90,
    }),
  });

  if (!chatResponse.ok) {
    throw new Error(
      `OpenAI-compatible request failed: ${await chatResponse.text()}`,
    );
  }

  const payload = await chatResponse.json();
  const content = asString(payload.choices?.[0]?.message?.content);
  const cleaned = cleanGeneratedText(content);
  if (!cleaned) {
    const error = new Error(
      "OpenAI-compatible provider returned empty content",
    );
    logProviderMetricFailure(metric, error, { apiPath: "chat_completions" });
    throw error;
  }

  logProviderMetricSuccess(metric, { apiPath: "chat_completions" });
  return cleaned;
}

export async function generateInteractionsWithFallback(
  apiKey: string,
  baseUrl: string,
  model: string,
  authorId: string,
  postId: string,
  postContent: string,
  topic: string,
  existingComments: ExistingComment[],
  viewerComment: string,
  allowedLikes: RankedContact[],
  allowedCommenters: RankedContact[],
): Promise<SanitizedInteractionResult> {
  const author = resolvePersonaProfile(authorId);
  const mode = viewerComment ? "reply" : "seed";

  const generatedAt = new Date().toISOString();
  const likes = viewerComment ? [] : allowedLikes.map((contact, index) => ({
    id: `like-${postId}-${contact.id}`,
    postId,
    authorId: contact.id,
    authorDisplayName: contact.displayName,
    reasonCode: contact.reasonCodes[0] ?? "close_tie",
    createdAt: new Date(Date.parse(generatedAt) + index * 1000).toISOString(),
  }));

  const comments: SanitizedInteractionResult["comments"] = [];
  const targets = viewerComment
    ? [authorId, ...allowedCommenters.map((contact) => contact.id)]
    : allowedCommenters.map((contact) => contact.id);

  for (const [index, targetId] of targets.entries()) {
    const targetPersona = resolvePersonaProfile(targetId);
    const matchedContact = allowedCommenters.find((contact) =>
      contact.id === targetId
    );
    const reason = matchedContact?.reasonCodes.join(", ") ||
      (targetId === authorId ? "author_reply" : "topic_match");
    const system = [
      `You are ${targetPersona.displayName}.`,
      personaSocialPrompt(targetId),
      "You are writing a short comment under a social feed post, not sending a DM.",
      "Be concise, natural, specific, and in character.",
      "Maximum: 2 short sentences.",
      "No bullet points. No hashtags. No explanations about being an AI.",
      "Mirror the language of the post thread.",
      "Do not pivot to politics or any new topic unless the viewer comment or post clearly brings it up.",
      "If the viewer comment is only a greeting or very short, reply with a brief natural nudge in character.",
    ].join(" ");

    const prompt = viewerComment
      ? targetId === authorId
        ? [
          "Reply to a viewer comment under your own post.",
          `Your original post: ${postContent}`,
          `Viewer comment: ${viewerComment}`,
          `Thread so far: ${
            existingComments.map((comment) =>
              `${comment.authorDisplayName}: ${comment.content}`
            ).join(" | ") || "none"
          }`,
          "Keep the reply anchored to the viewer comment. Do not invent a new subject.",
          `React directly and stay in character. Why you care: ${reason}.`,
        ].join("\n")
        : [
          "You were mentioned or have a clear reason to join the thread.",
          `Original post by ${author.displayName}: ${postContent}`,
          `Viewer comment: ${viewerComment}`,
          `Add one short follow-up comment in your own voice. Why you care: ${reason}.`,
        ].join("\n")
      : [
        `You are reacting to ${author.displayName}'s social post.`,
        `Post: ${postContent}`,
        `Topic: ${topic || "none"}`,
        `Reason you care: ${reason}.`,
        "Write one short realistic comment in your own voice.",
      ].join("\n");

    let content = "";
    let lastError: string | null = null;
    for (let attempt = 1; attempt <= MAX_GENERATION_RETRIES; attempt += 1) {
      try {
        content = await generateTextWithOpenAICompatible(
          apiKey,
          baseUrl,
          model,
          system,
          prompt,
          {
            postId,
            personaId: authorId,
            targetId,
            mode,
            attempt,
          },
        );
        content = sanitizeInteractionText(content, {
          postId,
          personaId: authorId,
          targetId,
          mode,
          source: "openai_compatible",
        });
        logGenerationEvent("openai_comment_success", {
          postId,
          authorId,
          targetId,
          mode: viewerComment ? "reply" : "seed",
          attempt,
          provider: "openai_compatible",
        });
        break;
      } catch (error) {
        lastError = error instanceof Error ? error.message : String(error);
        logGenerationEvent("openai_comment_failure", {
          postId,
          authorId,
          targetId,
          mode: viewerComment ? "reply" : "seed",
          attempt,
          provider: "openai_compatible",
          error: lastError,
        });
        if (attempt < MAX_GENERATION_RETRIES) {
          await delay(200 * attempt);
        }
      }
    }

    if (!content) {
      content = safeInteractionFallbackComment(
        targetId,
        author.displayName,
        viewerComment,
        {
          postId,
          personaId: authorId,
          mode,
        },
      );
      logGenerationEvent("openai_comment_fallback", {
        postId,
        authorId,
        targetId,
        mode: viewerComment ? "reply" : "seed",
        provider: "openai_compatible",
        retries: MAX_GENERATION_RETRIES,
        error: lastError,
      });
    }

    comments.push({
      id: `comment-${postId}-${targetId}-${crypto.randomUUID()}`,
      postId,
      authorId: targetId,
      authorDisplayName: targetPersona.displayName,
      content,
      reasonCode: targetId === authorId
        ? "author_reply"
        : matchedContact?.reasonCodes[0] ?? "topic_match",
      inReplyToCommentId: viewerComment && index === 0
        ? existingComments.at(-1)?.id ?? null
        : null,
      isViewer: false,
      createdAt: new Date(Date.parse(generatedAt) + index * 1000).toISOString(),
    });
  }

  return {
    postId,
    likes,
    comments,
    generatedAt,
    metadata: {
      usedAuthorFallback: false,
      generatedCommentCount: comments.length,
      generatedLikeCount: likes.length,
    },
  };
}

export async function generateThreadReplyWithOpenAICompatible(
  apiKey: string,
  baseUrl: string,
  model: string,
  postAuthorId: string,
  replyAuthorId: string,
  postId: string,
  postContent: string,
  topic: string,
  existingComments: ExistingComment[],
  viewerComment: string,
  viewerCommentId: string,
): Promise<SanitizedInteractionResult> {
  const postAuthor = resolvePersonaProfile(postAuthorId);
  const replyAuthor = resolvePersonaProfile(replyAuthorId);
  const replyAuthorDisplayName =
    existingComments.find((comment) => comment.authorId === replyAuthorId)
      ?.authorDisplayName ||
    replyAuthor.displayName;
  const generatedAt = new Date().toISOString();
  const priorThread = existingComments
    .map((comment) => `${comment.authorDisplayName}: ${comment.content}`)
    .join(" | ") || "none";

  const replyAuthorContext = existingComments
    .filter((comment) => comment.authorId === replyAuthorId)
    .map((comment) => comment.content)
    .join(" | ");

  const system = [
    `You are ${replyAuthorDisplayName}.`,
    personaSocialPrompt(replyAuthorId),
    "You are writing one short reply inside a WeChat Moments-style comment thread.",
    "Stay fully in character.",
    "Reply directly to the viewer comment, not like a DM and not like a long analysis.",
    "Be concise, natural, specific, and socially believable.",
    "Maximum: 2 short sentences.",
    "No bullet points. No hashtags. No AI disclaimers.",
    "Mirror the language of the thread.",
    "Do not invent a new topic unless the viewer comment clearly opens one.",
    "If the viewer comment is only a greeting or very short, answer with a short nudge in character.",
  ].join(" ");

  const prompt = [
    `Original post by ${postAuthor.displayName}: ${postContent}`,
    topic ? `Topic: ${topic}` : "Topic: none",
    postAuthorId == replyAuthorId
      ? "You are the post author replying under your own post."
      : `You are ${replyAuthorDisplayName}, a thread participant being replied to under ${postAuthor.displayName}'s post.`,
    replyAuthorContext
      ? `Your earlier thread context: ${replyAuthorContext}`
      : "Your earlier thread context: none",
    `Viewer comment: ${viewerComment}`,
    `Thread so far: ${priorThread}`,
    "Write exactly one short reply to the viewer comment.",
  ].join("\n\n");

  let content = "";
  let lastError: string | null = null;
  for (let attempt = 1; attempt <= MAX_GENERATION_RETRIES; attempt += 1) {
    try {
      content = await generateTextWithOpenAICompatible(
        apiKey,
        baseUrl,
        model,
        system,
        prompt,
        {
          postId,
          personaId: postAuthorId,
          targetId: replyAuthorId,
          mode: "reply",
          attempt,
        },
      );
      content = sanitizeInteractionText(content, {
        postId,
        personaId: postAuthorId,
        targetId: replyAuthorId,
        mode: "reply",
        source: "openai_compatible",
      });
      logGenerationEvent("openai_thread_reply_success", {
        postId,
        postAuthorId,
        replyAuthorId,
        attempt,
        provider: "openai_compatible",
      });
      break;
    } catch (error) {
      lastError = error instanceof Error ? error.message : String(error);
      logGenerationEvent("openai_thread_reply_failure", {
        postId,
        postAuthorId,
        replyAuthorId,
        attempt,
        provider: "openai_compatible",
        error: lastError,
      });
      if (attempt < MAX_GENERATION_RETRIES) {
        await delay(200 * attempt);
      }
    }
  }

  if (!content) {
    content = safeInteractionFallbackComment(
      replyAuthorId,
      postAuthor.displayName,
      viewerComment,
      {
        postId,
        personaId: postAuthorId,
        mode: "reply",
      },
    );
    logGenerationEvent("openai_thread_reply_fallback", {
      postId,
      postAuthorId,
      replyAuthorId,
      provider: "openai_compatible",
      retries: MAX_GENERATION_RETRIES,
      error: lastError,
    });
  }

  return {
    postId,
    likes: [],
    comments: [{
      id: `comment-${postId}-${replyAuthorId}-${crypto.randomUUID()}`,
      postId,
      authorId: replyAuthorId,
      authorDisplayName: replyAuthorDisplayName,
      content,
      reasonCode: replyAuthorId == postAuthorId
        ? "author_reply"
        : "thread_reply",
      inReplyToCommentId: viewerCommentId,
      isViewer: false,
      createdAt: generatedAt,
    }],
    generatedAt,
    metadata: {
      usedAuthorFallback: false,
      generatedCommentCount: 1,
      generatedLikeCount: 0,
    },
  };
}

export async function generateInteractionsWithClaude(
  apiKey: string,
  baseUrl: string,
  model: string,
  authorId: string,
  postContent: string,
  topic: string,
  existingComments: ExistingComment[],
  viewerComment: string,
  allowedLikes: RankedContact[],
  allowedCommenters: RankedContact[],
  metricDetails: Record<string, unknown> = {},
) {
  const metric = createProviderMetricContext(
    "generate-post-interactions",
    "interaction_batch",
    "anthropic",
    {
      model,
      ...metricDetails,
    },
  );
  const author = resolvePersonaProfile(authorId);

  const mode = viewerComment ? "reply" : "seed";
  const allowedIds = new Set([
    ...allowedLikes.map((contact) => contact.id),
    ...allowedCommenters.map((contact) => contact.id),
    ...(viewerComment ? [authorId] : []),
  ]);
  const contactLookups = [...allowedLikes, ...allowedCommenters];

  const allowedContacts = [
    authorId,
    ...Array.from(allowedIds).filter((id) => id !== authorId),
  ]
    .map((id) => {
      if (id === authorId) {
        return {
          id,
          displayName: author.displayName,
          stance: author.stance,
          relationshipHint: "Post author",
        };
      }

      const contact = contactLookups.find((item) => item.id === id);
      return contact
        ? {
          id: contact.id,
          displayName: contact.displayName,
          stance: contact.stance,
          relationshipHint: contact.relationshipHint,
        }
        : null;
    })
    .filter((item): item is NonNullable<typeof item> => item !== null);

  const response = await fetch(`${baseUrl}/v1/messages`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "x-api-key": apiKey,
      "anthropic-version": "2023-06-01",
    },
    body: JSON.stringify({
      model,
      max_tokens: 700,
      temperature: 0.2,
      system: [
        "You design believable social interactions for a WeChat Moments-style feed.",
        "Never invent people outside the allowed contacts.",
        "Every interaction must feel motivated by relationship, mentions, topic overlap, or thread context.",
        "Do not produce generic praise unless the persona would genuinely say it.",
        "Mirror the primary language of the post thread.",
        "Keep comments concise and social: usually 1 sentence, max 2 short sentences.",
        "Stay faithful to each persona's speaking style and worldview.",
        "If mode is reply, the post author must reply directly to the viewer comment.",
        "If mode is reply, keep the reply anchored to the viewer comment and do not invent a new topic.",
        "If the viewer comment is just a greeting or very short, answer with a short nudge in character.",
        "If mode is seed, only non-author contacts can comment.",
        "Return the result only through the tool call.",
      ].join(" "),
      messages: [{
        role: "user",
        content: [
          {
            type: "text",
            text: [
              `Mode: ${mode}`,
              `Post author: ${author.displayName} (${authorId})`,
              `Author stance: ${author.stance}`,
              `Post topic: ${topic || "none"}`,
              `Post content:\n${postContent}`,
              viewerComment
                ? `Viewer comment:\n${viewerComment}`
                : "Viewer comment: none",
              existingComments.length > 0
                ? `Existing thread:\n${
                  existingComments.map((comment) =>
                    `- ${comment.authorDisplayName} (${comment.authorId}): ${comment.content}`
                  ).join("\n")
                }`
                : "Existing thread: none",
              `Allowed contacts:\n${
                allowedContacts.map((contact) =>
                  `- ${contact.displayName} (${contact.id}): ${contact.stance}. ${contact.relationshipHint}`
                ).join("\n")
              }`,
              `Allowed like authors: ${
                allowedLikes.map((contact) => contact.id).join(", ") || "none"
              }`,
              `Allowed comment authors: ${
                (viewerComment
                  ? [
                    authorId,
                    ...allowedCommenters.map((contact) => contact.id),
                  ]
                  : allowedCommenters.map((contact) => contact.id)).join(
                    ", ",
                  ) || "none"
              }`,
              "Allowed reason codes: mention_hit, topic_match, domain_fit, close_tie, thread_participant, author_reply, competitive_take.",
            ].join("\n\n"),
          },
        ],
      }],
      tools: [{
        name: "submit_interactions",
        description:
          "Return final likes and comments for this post interaction.",
        input_schema: {
          type: "object",
          properties: {
            likes: {
              type: "array",
              items: {
                type: "object",
                properties: {
                  authorId: { type: "string" },
                  reasonCode: { type: "string" },
                },
                required: ["authorId", "reasonCode"],
              },
            },
            comments: {
              type: "array",
              items: {
                type: "object",
                properties: {
                  authorId: { type: "string" },
                  content: { type: "string" },
                  reasonCode: { type: "string" },
                  inReplyToCommentId: {
                    anyOf: [
                      { type: "string" },
                      { type: "null" },
                    ],
                  },
                },
                required: ["authorId", "content", "reasonCode"],
              },
            },
          },
          required: ["likes", "comments"],
        },
      }],
      tool_choice: {
        type: "tool",
        name: "submit_interactions",
      },
    }),
  });

  if (!response.ok) {
    const error = new Error(
      `Anthropic request failed: ${await response.text()}`,
    );
    logProviderMetricFailure(metric, error);
    throw error;
  }

  const payload = await response.json();
  const blocks = Array.isArray(payload.content) ? payload.content : [];
  const toolBlock = blocks.find((block: Record<string, unknown>) =>
    block.type === "tool_use" && block.name === "submit_interactions"
  );
  if (!toolBlock || typeof toolBlock !== "object") {
    const error = new Error("Anthropic did not return a tool payload");
    logProviderMetricFailure(metric, error);
    throw error;
  }

  logProviderMetricSuccess(metric);
  return (toolBlock.input ?? {}) as ToolPayload;
}

export function sanitizeGeneratedPayload(
  payload: ToolPayload,
  postId: string,
  authorId: string,
  viewerComment: string,
  allowedLikes: RankedContact[],
  allowedCommenters: RankedContact[],
  existingComments: ExistingComment[],
): SanitizedInteractionResult {
  const mode = viewerComment ? "reply" : "seed";
  const allowedLikeIds = new Set(allowedLikes.map((contact) => contact.id));
  const allowedCommentIds = new Set(
    allowedCommenters.map((contact) => contact.id),
  );
  if (mode === "reply") {
    allowedCommentIds.add(authorId);
  }

  const generatedAt = new Date().toISOString();
  const likes = (payload.likes ?? [])
    .map((item) => ({
      authorId: asString(item.authorId),
      reasonCode: asString(item.reasonCode) || "close_tie",
    }))
    .filter((item) => allowedLikeIds.has(item.authorId))
    .filter((item, index, array) =>
      array.findIndex((candidate) => candidate.authorId === item.authorId) ===
        index
    )
    .map((item, index) => ({
      id: `like-${postId}-${item.authorId}`,
      postId,
      authorId: item.authorId,
      authorDisplayName: displayNameFor(item.authorId),
      reasonCode: item.reasonCode,
      createdAt: new Date(Date.parse(generatedAt) + index * 1000).toISOString(),
    }));

  const comments = (payload.comments ?? [])
    .map((item) => ({
      authorId: asString(item.authorId),
      content: sanitizeInteractionText(asString(item.content), {
        postId,
        personaId: authorId,
        targetId: asString(item.authorId),
        mode,
        source: "anthropic",
      }),
      reasonCode: asString(item.reasonCode) ||
        (viewerComment ? "author_reply" : "topic_match"),
      inReplyToCommentId: asString(item.inReplyToCommentId) || null,
    }))
    .filter((item) =>
      item.content.length > 0 && allowedCommentIds.has(item.authorId)
    )
    .filter((item) => mode === "reply" || item.authorId !== authorId)
    .slice(0, 2)
    .map((item, index) => ({
      id: `comment-${postId}-${item.authorId}-${crypto.randomUUID()}`,
      postId,
      authorId: item.authorId,
      authorDisplayName: displayNameFor(item.authorId),
      content: item.content,
      reasonCode: item.reasonCode,
      inReplyToCommentId: item.inReplyToCommentId ??
        (viewerComment && index === 0
          ? existingComments.at(-1)?.id ?? null
          : null),
      isViewer: false,
      createdAt: new Date(Date.parse(generatedAt) + index * 1000).toISOString(),
    }));

  if (mode === "reply") {
    const generatedAuthorReply = comments.find((item) =>
      item.authorId === authorId
    ) ?? null;
    const authorReply = generatedAuthorReply ?? {
      id: `comment-${postId}-${authorId}-${crypto.randomUUID()}`,
      postId,
      authorId,
      authorDisplayName: displayNameFor(authorId),
      content: safeInteractionFallbackComment(
        authorId,
        displayNameFor(authorId),
        viewerComment,
        {
          postId,
          personaId: authorId,
          mode,
        },
      ),
      reasonCode: "author_reply",
      inReplyToCommentId: existingComments.at(-1)?.id ?? null,
      isViewer: false,
      createdAt: generatedAt,
    };

    const followUp = comments.find((item) => item.authorId !== authorId) ??
      null;
    return {
      postId,
      likes: [],
      comments: followUp ? [authorReply, followUp] : [authorReply],
      generatedAt,
      metadata: {
        usedAuthorFallback: generatedAuthorReply === null,
        generatedCommentCount: comments.length,
        generatedLikeCount: likes.length,
      },
    };
  }

  return {
    postId,
    likes: mode === "seed" ? likes : [],
    comments,
    generatedAt,
    metadata: {
      usedAuthorFallback: false,
      generatedCommentCount: comments.length,
      generatedLikeCount: likes.length,
    },
  };
}

export function shouldAcceptSanitizedResult(
  result: SanitizedInteractionResult,
  authorId: string,
  viewerComment: string,
  allowedCommenters: RankedContact[],
): boolean {
  if (viewerComment) {
    const hasAuthorReply = result.comments.some((item) =>
      item.authorId === authorId
    );
    return hasAuthorReply && !result.metadata.usedAuthorFallback;
  }

  if (allowedCommenters.length === 0) {
    return true;
  }

  return result.comments.length > 0 || result.likes.length > 0;
}

export async function tryAnthropicSeedInteractions(
  anthropicApiKey: string | undefined,
  anthropicBaseUrl: string,
  anthropicModels: string[],
  personaId: string,
  postId: string,
  postContent: string,
  topic: string,
  allowedLikes: RankedContact[],
  allowedCommenters: RankedContact[],
): Promise<SanitizedInteractionResult | null> {
  if (!anthropicApiKey) return null;

  modelLoop:
  for (const anthropicModel of anthropicModels) {
    for (let attempt = 1; attempt <= MAX_GENERATION_RETRIES; attempt += 1) {
      try {
        const candidate = sanitizeGeneratedPayload(
          await generateInteractionsWithClaude(
            anthropicApiKey,
            anthropicBaseUrl,
            anthropicModel,
            personaId,
            postContent,
            topic,
            [],
            "",
            allowedLikes,
            allowedCommenters,
            {
              postId,
              personaId,
              mode: "seed",
              attempt,
            },
          ),
          postId,
          personaId,
          "",
          allowedLikes,
          allowedCommenters,
          [],
        );

        if (
          shouldAcceptSanitizedResult(
            candidate,
            personaId,
            "",
            allowedCommenters,
          )
        ) {
          logGenerationEvent("anthropic_seed_success", {
            postId,
            personaId,
            attempt,
            model: anthropicModel,
            provider: "anthropic",
            generatedCommentCount: candidate.metadata.generatedCommentCount,
            generatedLikeCount: candidate.metadata.generatedLikeCount,
          });
          return candidate;
        }

        logGenerationEvent("anthropic_seed_rejected", {
          postId,
          personaId,
          attempt,
          model: anthropicModel,
          provider: "anthropic",
          generatedCommentCount: candidate.metadata.generatedCommentCount,
          generatedLikeCount: candidate.metadata.generatedLikeCount,
          usedAuthorFallback: candidate.metadata.usedAuthorFallback,
        });
      } catch (error) {
        const errorMessage = error instanceof Error
          ? error.message
          : String(error);
        logGenerationEvent("anthropic_seed_failure", {
          postId,
          personaId,
          attempt,
          model: anthropicModel,
          provider: "anthropic",
          error: errorMessage,
        });

        if (isTerminalAnthropicError(errorMessage)) {
          break modelLoop;
        }
      }

      if (attempt < MAX_GENERATION_RETRIES) {
        await delay(200 * attempt);
      }
    }
  }

  return null;
}

export async function tryAnthropicReplyInteractions(
  anthropicApiKey: string | undefined,
  anthropicBaseUrl: string,
  anthropicModels: string[],
  personaId: string,
  postId: string,
  postContent: string,
  topic: string,
  existingComments: ExistingComment[],
  viewerComment: string,
  allowedCommenters: RankedContact[],
): Promise<SanitizedInteractionResult | null> {
  if (!anthropicApiKey) return null;

  modelLoop:
  for (const anthropicModel of anthropicModels) {
    for (let attempt = 1; attempt <= MAX_GENERATION_RETRIES; attempt += 1) {
      try {
        const candidate = sanitizeGeneratedPayload(
          await generateInteractionsWithClaude(
            anthropicApiKey,
            anthropicBaseUrl,
            anthropicModel,
            personaId,
            postContent,
            topic,
            existingComments,
            viewerComment,
            [],
            allowedCommenters,
            {
              postId,
              personaId,
              mode: "reply",
              attempt,
            },
          ),
          postId,
          personaId,
          viewerComment,
          [],
          allowedCommenters,
          existingComments,
        );

        if (
          shouldAcceptSanitizedResult(
            candidate,
            personaId,
            viewerComment,
            allowedCommenters,
          )
        ) {
          logGenerationEvent("anthropic_reply_success", {
            postId,
            personaId,
            attempt,
            model: anthropicModel,
            provider: "anthropic",
            generatedCommentCount: candidate.metadata.generatedCommentCount,
            usedAuthorFallback: candidate.metadata.usedAuthorFallback,
          });
          return candidate;
        }

        logGenerationEvent("anthropic_reply_rejected", {
          postId,
          personaId,
          attempt,
          model: anthropicModel,
          provider: "anthropic",
          generatedCommentCount: candidate.metadata.generatedCommentCount,
          usedAuthorFallback: candidate.metadata.usedAuthorFallback,
        });
      } catch (error) {
        const errorMessage = error instanceof Error
          ? error.message
          : String(error);
        logGenerationEvent("anthropic_reply_failure", {
          postId,
          personaId,
          attempt,
          model: anthropicModel,
          provider: "anthropic",
          error: errorMessage,
        });

        if (isTerminalAnthropicError(errorMessage)) {
          break modelLoop;
        }
      }

      if (attempt < MAX_GENERATION_RETRIES) {
        await delay(200 * attempt);
      }
    }
  }

  return null;
}
