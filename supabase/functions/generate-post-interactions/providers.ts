import {
  extractOpenAICompatibleContent,
  extractOpenAICompatibleError,
  formatOpenAICompatiblePayloadSummary,
} from "../_shared/openai_compatible.ts";
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
  let responsesError: string | null = null;
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
    const providerError = extractOpenAICompatibleError(payload);
    if (providerError) {
      responsesError = providerError;
    }
    const content = extractOpenAICompatibleContent(payload);

    if (content) {
      const cleaned = cleanGeneratedText(content);
      if (cleaned) {
        logProviderMetricSuccess(metric, { apiPath: "responses" });
        return cleaned;
      }
    }
    responsesError = responsesError ??
      formatOpenAICompatiblePayloadSummary(payload);
  } else {
    responsesError = await responsesRequest.text();
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
  const providerError = extractOpenAICompatibleError(payload);
  if (providerError) {
    const error = new Error(providerError);
    logProviderMetricFailure(metric, error, {
      apiPath: "chat_completions",
      responsesError,
    });
    throw error;
  }
  const content = extractOpenAICompatibleContent(payload);
  const cleaned = cleanGeneratedText(content);
  if (!cleaned) {
    const error = new Error(
      `OpenAI-compatible provider returned empty content. chat=${
        formatOpenAICompatiblePayloadSummary(payload)
      }${responsesError ? `; responses=${responsesError}` : ""}`,
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
