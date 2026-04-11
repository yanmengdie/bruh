import { createClient } from "jsr:@supabase/supabase-js@2";
import { sanitizeExternalContent } from "../_shared/content_safety.ts";
import { corsHeaders } from "../_shared/cors.ts";
import { resolveSupabaseServiceConfig } from "../_shared/environment.ts";
import {
  createObservationContext,
  logEdgeEvent,
  logEdgeFailure,
  logEdgeStart,
  logEdgeSuccess,
} from "../_shared/observability.ts";

type IncomingNote = {
  noteId?: string;
  title?: string;
  rawText?: string;
  noteUrl?: string;
  exploreUrl?: string;
  coverImageUrl?: string;
  imageUrls?: string[];
  videoUrl?: string;
  likeCount?: string | number;
  isPinned?: boolean;
  publishedAt?: string;
  rawPayload?: Record<string, unknown>;
};

function asString(value: unknown): string {
  return typeof value === "string" ? value.trim() : "";
}

function slugify(value: string): string {
  const normalized = value
    .trim()
    .toLowerCase()
    .replace(/[^a-z0-9\u4e00-\u9fa5]+/g, "-")
    .replace(/^-+|-+$/g, "");

  return normalized || crypto.randomUUID();
}

function parseCount(value: unknown): number {
  if (typeof value === "number" && Number.isFinite(value)) return value;
  if (typeof value !== "string") return 0;

  const normalized = value.trim().replace(/,/g, "");
  if (!normalized) return 0;

  if (normalized.endsWith("万")) {
    const parsed = Number.parseFloat(normalized.slice(0, -1));
    return Number.isFinite(parsed) ? Math.round(parsed * 10000) : 0;
  }

  const parsed = Number.parseFloat(normalized);
  return Number.isFinite(parsed) ? parsed : 0;
}

function stripQuery(url: string): string {
  const trimmed = url.trim();
  if (!trimmed) return "";

  try {
    const parsed = new URL(trimmed);
    parsed.search = "";
    parsed.hash = "";
    return parsed.toString();
  } catch {
    return trimmed.split("?")[0] ?? trimmed;
  }
}

function normalizePreservingQuery(url: string): string {
  const trimmed = asString(url);
  if (!trimmed) return "";
  return trimmed.replace(/^http:\/\//i, "https://");
}

function normalizeUrlList(values: unknown): string[] {
  if (!Array.isArray(values)) return [];

  const unique = new Set<string>();
  for (const value of values) {
    const normalized = stripQuery(asString(value));
    if (!normalized || !/^https?:\/\//i.test(normalized)) continue;
    unique.add(normalized);
  }

  return [...unique];
}

function extractMediaUrls(note: IncomingNote): string[] {
  const directUrls = normalizeUrlList(note.imageUrls);
  if (directUrls.length > 0) return directUrls.slice(0, 9);

  const coverImageUrl = stripQuery(asString(note.coverImageUrl));
  if (coverImageUrl && /^https?:\/\//i.test(coverImageUrl)) {
    return [coverImageUrl];
  }

  const rawPayload = note.rawPayload ?? {};
  const payloadUrls = normalizeUrlList(
    (rawPayload as Record<string, unknown>).imageUrls,
  );
  if (payloadUrls.length > 0) return payloadUrls.slice(0, 9);

  const payloadCover = stripQuery(
    asString((rawPayload as Record<string, unknown>).coverImageUrl),
  );
  if (payloadCover && /^https?:\/\//i.test(payloadCover)) {
    return [payloadCover];
  }

  return [];
}

function preferredSourceUrl(
  note: IncomingNote,
  profileUrl: string | null,
): string | null {
  const noteUrl = stripQuery(asString(note.noteUrl));
  if (noteUrl) return noteUrl;

  const exploreUrl = stripQuery(asString(note.exploreUrl));
  if (exploreUrl) return exploreUrl;

  return profileUrl ? stripQuery(profileUrl) : null;
}

function sanitizeNote(note: IncomingNote): Record<string, unknown> {
  const mediaUrls = extractMediaUrls(note);
  const videoUrl = normalizePreservingQuery(asString(note.videoUrl));
  const safeTitle = sanitizeExternalContent(asString(note.title), {
    maxLength: 160,
  });
  const safeRawText = sanitizeExternalContent(asString(note.rawText), {
    maxLength: 240,
  });

  return {
    noteId: asString(note.noteId),
    title: safeTitle.blocked ? "" : safeTitle.text,
    rawText: safeRawText.blocked ? "" : safeRawText.text,
    noteUrl: stripQuery(asString(note.noteUrl)),
    exploreUrl: stripQuery(asString(note.exploreUrl)),
    coverImageUrl: mediaUrls[0] ?? "",
    imageUrls: mediaUrls,
    videoUrl,
    likeCount: note.likeCount ?? null,
    isPinned: note.isPinned === true,
    publishedAt: asString(note.publishedAt),
    rawPayload: note.rawPayload ?? null,
  };
}

function computeImportanceScore(note: IncomingNote): number {
  const likes = parseCount(note.likeCount);
  const pinnedBoost = note.isPinned ? 0.08 : 0;
  const rawScore = 0.52 + Math.min(likes / 5000, 0.39) + pinnedBoost;
  return Math.round(Math.min(rawScore, 0.99) * 100) / 100;
}

function extractContent(note: IncomingNote): string {
  const title = sanitizeExternalContent(asString(note.title), {
    maxLength: 160,
  });
  if (!title.blocked && title.text.length > 0) return title.text;

  const rawText = asString(note.rawText)
    .replace(/\s+/g, " ")
    .trim();

  if (rawText.length === 0) {
    return "小红书新动态";
  }

  const safeRawText = sanitizeExternalContent(rawText, { maxLength: 160 });
  if (!safeRawText.blocked && safeRawText.text) {
    return safeRawText.text;
  }

  return "小红书新动态";
}

function resolvePublishedAt(note: IncomingNote, index: number): string {
  const candidate = asString(note.publishedAt);
  if (candidate) {
    const date = new Date(candidate);
    if (!Number.isNaN(date.getTime())) {
      return date.toISOString();
    }
  }

  return new Date(Date.now() - index * 1000).toISOString();
}

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  const observation = createObservationContext("ingest-xhs-posts");
  logEdgeStart(observation, "job_started", {
    method: request.method,
  });

  try {
    const { projectUrl, serviceRoleKey } = resolveSupabaseServiceConfig();
    const body = request.method === "POST"
      ? await request.json().catch(() => ({}))
      : {};
    const displayName = asString(body.displayName);
    const personaId = asString(body.personaId) || displayName;
    const userId = asString(body.userId);
    const sourceHandle = asString(body.sourceHandle) ||
      `xhs:${userId || slugify(displayName || personaId)}`;
    const profileUrl = asString(body.profileUrl) || null;
    const notes = Array.isArray(body.notes) ? body.notes as IncomingNote[] : [];
    const contentSafety = { blocked: 0, sanitized: 0 };

    if (!displayName || !personaId) {
      logEdgeSuccess(observation, "request_rejected", { status: 400 });
      return Response.json(
        { error: "Missing displayName or personaId" },
        { status: 400, headers: corsHeaders },
      );
    }

    if (notes.length === 0) {
      logEdgeSuccess(observation, "request_rejected", { status: 400 });
      return Response.json(
        { error: "No notes provided" },
        { status: 400, headers: corsHeaders },
      );
    }

    const supabase = createClient(projectUrl, serviceRoleKey);

    const { error: personaError } = await supabase
      .from("personas")
      .upsert({
        id: personaId,
        x_username: sourceHandle,
        display_name: displayName,
        is_active: true,
      }, { onConflict: "id" });

    if (personaError) {
      throw new Error(personaError.message);
    }

    const rows = notes.map((note, index) => {
      const noteId = asString(note.noteId) || crypto.randomUUID();
      const mediaUrls = extractMediaUrls(note);
      const videoUrl = normalizePreservingQuery(asString(note.videoUrl)) ||
        null;
      const content = extractContent(note);
      if (content === "小红书新动态") {
        const titleSafety = sanitizeExternalContent(asString(note.title), {
          maxLength: 160,
        });
        const rawTextSafety = sanitizeExternalContent(asString(note.rawText), {
          maxLength: 160,
        });
        if (titleSafety.blocked || rawTextSafety.blocked) {
          contentSafety.blocked += 1;
        }
      } else {
        const titleSafety = sanitizeExternalContent(asString(note.title), {
          maxLength: 160,
        });
        const rawTextSafety = sanitizeExternalContent(asString(note.rawText), {
          maxLength: 160,
        });
        if (titleSafety.sanitized || rawTextSafety.sanitized) {
          contentSafety.sanitized += 1;
        }
      }

      return {
        id: `xhs-${slugify(personaId)}-${noteId}`,
        persona_id: personaId,
        source_type: "xiaohongshu",
        content,
        source_url: preferredSourceUrl(note, profileUrl),
        topic: "小红书",
        importance_score: computeImportanceScore(note),
        published_at: resolvePublishedAt(note, index),
        media_urls: mediaUrls,
        video_url: videoUrl,
        raw_author_username: displayName,
        raw_payload: {
          platform: "xiaohongshu",
          displayName,
          personaId,
          userId,
          profileUrl: profileUrl ? stripQuery(profileUrl) : null,
          mediaUrls,
          videoUrl,
          note: sanitizeNote(note),
        },
      };
    });

    if (contentSafety.blocked > 0 || contentSafety.sanitized > 0) {
      logEdgeEvent("ingest-xhs-posts", "content_safety_applied", {
        blocked: contentSafety.blocked,
        sanitized: contentSafety.sanitized,
        noteCount: notes.length,
      });
    }

    const { data, error: upsertError } = await supabase
      .from("source_posts")
      .upsert(rows, { onConflict: "id" })
      .select("id");

    if (upsertError) {
      throw new Error(upsertError.message);
    }

    logEdgeSuccess(observation, "job_succeeded", {
      personaId,
      noteCount: rows.length,
      inserted: data?.length ?? rows.length,
    });
    return Response.json(
      {
        ok: true,
        personaId,
        displayName,
        inserted: data?.length ?? rows.length,
        notes: rows.length,
      },
      { headers: corsHeaders },
    );
  } catch (error) {
    logEdgeFailure(observation, "request_failed", error);
    return Response.json(
      { error: error instanceof Error ? error.message : "Unknown error" },
      { status: 500, headers: corsHeaders },
    );
  }
});
