export type ExistingComment = {
  id: string;
  authorId: string;
  authorDisplayName: string;
  content: string;
  isViewer: boolean;
  inReplyToCommentId: string | null;
};

export type StoredLikeRow = {
  id: string;
  post_id: string;
  author_id: string;
  author_type: string;
  author_display_name: string;
  reason_code: string;
  created_at: string;
};

export type StoredCommentRow = {
  id: string;
  post_id: string;
  author_id: string;
  author_type: string;
  author_display_name: string;
  content: string;
  reason_code: string;
  in_reply_to_comment_id: string | null;
  generation_mode: string;
  created_at: string;
};

export type ContactProfile = {
  id: string;
  username: string;
  displayName: string;
  stance: string;
  domains: string[];
  triggerKeywords: string[];
  relationshipHint: string;
};

export type RankedContact = ContactProfile & {
  score: number;
  reasonCodes: string[];
};

export type PersonaProfile = {
  personaId: string;
  displayName: string;
  stance: string;
  domains: string[];
  triggerKeywords: string[];
};

export type ToolPayload = {
  likes?: Array<{
    authorId?: unknown;
    reasonCode?: unknown;
  }>;
  comments?: Array<{
    authorId?: unknown;
    content?: unknown;
    reasonCode?: unknown;
    inReplyToCommentId?: unknown;
  }>;
};

export type InteractionLike = {
  id: string;
  postId: string;
  authorId: string;
  authorDisplayName: string;
  reasonCode: string;
  createdAt: string;
};

export type InteractionComment = {
  id: string;
  postId: string;
  authorId: string;
  authorDisplayName: string;
  content: string;
  reasonCode: string;
  inReplyToCommentId: string | null;
  isViewer: boolean;
  createdAt: string;
};

export type SanitizedInteractionResult = {
  postId: string;
  likes: InteractionLike[];
  comments: InteractionComment[];
  generatedAt: string;
  metadata: {
    usedAuthorFallback: boolean;
    generatedCommentCount: number;
    generatedLikeCount: number;
  };
};
