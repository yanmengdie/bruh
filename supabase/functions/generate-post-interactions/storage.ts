import { asString, normalizeBoolean } from "./helpers.ts";
import { normalizeLegacyFallbackComment } from "./fallbacks.ts";
import type {
  ExistingComment,
  InteractionComment,
  InteractionLike,
  StoredCommentRow,
  StoredLikeRow,
} from "./types.ts";

export function mapStoredState(
  postId: string,
  likes: StoredLikeRow[],
  comments: StoredCommentRow[],
) {
  return {
    postId,
    likes: likes.map((item) => ({
      id: item.id,
      postId: item.post_id,
      authorId: item.author_id,
      authorDisplayName: item.author_display_name,
      reasonCode: item.reason_code,
      createdAt: item.created_at,
    })),
    comments: comments.map((item) => ({
      id: item.id,
      postId: item.post_id,
      authorId: item.author_id,
      authorDisplayName: item.author_display_name,
      content: normalizeLegacyFallbackComment(item.author_id, item.content),
      reasonCode: item.reason_code,
      inReplyToCommentId: item.in_reply_to_comment_id,
      isViewer: item.author_type === "viewer",
      createdAt: item.created_at,
    })),
    generatedAt: new Date().toISOString(),
  };
}

export function mapTransientState(
  postId: string,
  likes: StoredLikeRow[],
  comments: StoredCommentRow[],
) {
  return mapStoredState(postId, likes, comments);
}

export function normalizeStoredComments(
  rows: StoredCommentRow[],
): ExistingComment[] {
  return rows.map((row) => ({
    id: row.id,
    authorId: row.author_id,
    authorDisplayName: row.author_display_name,
    content: normalizeLegacyFallbackComment(row.author_id, row.content),
    isViewer: row.author_type === "viewer",
    inReplyToCommentId: row.in_reply_to_comment_id,
  }));
}

export function normalizeTransientLikes(
  value: unknown,
  postId: string,
): StoredLikeRow[] {
  if (!Array.isArray(value)) return [];

  return value
    .map((item) => item as Record<string, unknown>)
    .map((row) => {
      const id = asString(row.id);
      const authorId = asString(row.authorId);
      const authorDisplayName = asString(row.authorDisplayName);
      const reasonCode = asString(row.reasonCode) || "close_tie";
      const createdAt = asString(row.createdAt) || new Date().toISOString();
      if (!id || !authorId || !authorDisplayName) return null;
      return {
        id,
        post_id: asString(row.postId) || postId,
        author_id: authorId,
        author_type: authorId === "viewer" ? "viewer" : "persona",
        author_display_name: authorDisplayName,
        reason_code: reasonCode,
        created_at: createdAt,
      } satisfies StoredLikeRow;
    })
    .filter((item): item is StoredLikeRow => item !== null);
}

export function normalizeTransientComments(
  value: unknown,
  postId: string,
): StoredCommentRow[] {
  if (!Array.isArray(value)) return [];

  return value
    .map((item) => item as Record<string, unknown>)
    .map((row) => {
      const id = asString(row.id);
      const authorId = asString(row.authorId);
      const authorDisplayName = asString(row.authorDisplayName);
      const content = normalizeLegacyFallbackComment(
        authorId,
        asString(row.content),
      );
      const createdAt = asString(row.createdAt) || new Date().toISOString();
      if (!id || !authorId || !authorDisplayName || !content) return null;
      return {
        id,
        post_id: asString(row.postId) || postId,
        author_id: authorId,
        author_type: normalizeBoolean(row.isViewer, authorId === "viewer")
          ? "viewer"
          : "persona",
        author_display_name: authorDisplayName,
        content,
        reason_code: asString(row.reasonCode) ||
          (authorId === "viewer" ? "viewer_input" : "topic_match"),
        in_reply_to_comment_id: asString(row.inReplyToCommentId) || null,
        generation_mode: asString(row.generationMode) ||
          (authorId === "viewer" ? "viewer" : "seed"),
        created_at: createdAt,
      } satisfies StoredCommentRow;
    })
    .filter((item): item is StoredCommentRow => item !== null);
}

export function toStoredLikeRows(likes: InteractionLike[]): StoredLikeRow[] {
  return likes.map((item) => ({
    id: item.id,
    post_id: item.postId,
    author_id: item.authorId,
    author_type: item.authorId === "viewer" ? "viewer" : "persona",
    author_display_name: item.authorDisplayName,
    reason_code: item.reasonCode,
    created_at: item.createdAt,
  }));
}

export function toStoredCommentRows(
  comments: InteractionComment[],
  generationMode: "seed" | "reply" | "viewer",
): StoredCommentRow[] {
  return comments.map((item) => ({
    id: item.id,
    post_id: item.postId,
    author_id: item.authorId,
    author_type: item.isViewer ? "viewer" : "persona",
    author_display_name: item.authorDisplayName,
    content: item.content,
    reason_code: item.reasonCode,
    in_reply_to_comment_id: item.inReplyToCommentId,
    generation_mode: generationMode,
    created_at: item.createdAt,
  }));
}

export async function fetchStoredState(supabase: any, postId: string) {
  const { data: likes, error: likesError } = await supabase
    .from("feed_likes")
    .select(
      "id, post_id, author_id, author_type, author_display_name, reason_code, created_at",
    )
    .eq("post_id", postId)
    .order("created_at", { ascending: true });

  if (likesError && !likesError.message.includes("feed_likes")) {
    throw new Error(likesError.message);
  }

  const { data: comments, error: commentsError } = await supabase
    .from("feed_comments")
    .select(
      "id, post_id, author_id, author_type, author_display_name, content, reason_code, in_reply_to_comment_id, generation_mode, created_at",
    )
    .eq("post_id", postId)
    .order("created_at", { ascending: true });

  if (commentsError && !commentsError.message.includes("feed_comments")) {
    throw new Error(commentsError.message);
  }

  return {
    likes: (likes ?? []) as StoredLikeRow[],
    comments: (comments ?? []) as StoredCommentRow[],
  };
}

export async function persistLikes(supabase: any, likes: InteractionLike[]) {
  if (likes.length === 0) return;

  const rows = likes.map((item) => ({
    id: item.id,
    post_id: item.postId,
    author_id: item.authorId,
    author_type: item.authorId === "viewer" ? "viewer" : "persona",
    author_display_name: item.authorDisplayName,
    reason_code: item.reasonCode,
    created_at: item.createdAt,
  }));

  const { error } = await supabase
    .from("feed_likes")
    .upsert(rows, { onConflict: "post_id,author_id" });

  if (error) {
    throw new Error(error.message);
  }
}

export async function persistComments(
  supabase: any,
  comments: Array<
    InteractionComment & {
      generationMode: "seed" | "reply" | "viewer";
    }
  >,
) {
  if (comments.length === 0) return;

  const rows = comments.map((item) => ({
    id: item.id,
    post_id: item.postId,
    author_id: item.authorId,
    author_type: item.isViewer ? "viewer" : "persona",
    author_display_name: item.authorDisplayName,
    content: item.content,
    reason_code: item.reasonCode,
    in_reply_to_comment_id: item.inReplyToCommentId,
    generation_mode: item.generationMode,
    created_at: item.createdAt,
  }));

  const { error } = await supabase
    .from("feed_comments")
    .upsert(rows);

  if (error) {
    throw new Error(error.message);
  }
}
