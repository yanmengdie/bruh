import { personaMap, resolvePersonaById } from "../_shared/personas.ts";
import type {
  ContactProfile,
  ExistingComment,
  RankedContact,
} from "./types.ts";

function keywordOverlapScore(text: string, keywords: string[]): number {
  const lower = text.toLowerCase();
  return keywords.reduce(
    (score, keyword) => score + (lower.includes(keyword.toLowerCase()) ? 1 : 0),
    0,
  );
}

function relationshipHint(authorId: string, contactId: string): string {
  const hints: Record<string, Record<string, string>> = {
    musk: {
      trump:
        "High-profile political ally who jumps into policy, tariffs, and culture-war topics.",
    },
    trump: {
      musk:
        "Political ally who reacts when business, AI, or national power is involved.",
    },
  };

  return hints[authorId]?.[contactId] ??
    "Knows the author and comments only when the topic clearly connects.";
}

function acquaintanceIdsFor(authorId: string): string[] {
  return Object.keys(
    ({
      musk: {
        trump: true,
      },
      trump: {
        musk: true,
      },
    } as Record<string, Record<string, boolean>>)[authorId] ?? {},
  );
}

function allContactsFor(authorId: string): ContactProfile[] {
  const knownIds = new Set(acquaintanceIdsFor(authorId));

  return Object.entries(personaMap)
    .map(([username, persona]) => ({
      id: persona.personaId,
      username,
      displayName: persona.displayName,
      stance: persona.stance,
      domains: persona.domains,
      triggerKeywords: persona.triggerKeywords,
      relationshipHint: relationshipHint(authorId, persona.personaId),
    }))
    .filter((contact) => contact.id !== authorId && knownIds.has(contact.id));
}

function extractMentionedPersonaIds(texts: string[]): Set<string> {
  const joined = texts.join("\n").toLowerCase();
  const mentions = new Set<string>();

  for (const [username, persona] of Object.entries(personaMap)) {
    const tokens = [
      username,
      persona.personaId,
      persona.displayName.toLowerCase(),
      `@${username}`,
      `@${persona.personaId}`,
    ];

    if (tokens.some((token) => token.length > 0 && joined.includes(token))) {
      mentions.add(persona.personaId);
    }
  }

  return mentions;
}

export function rankContacts(
  authorId: string,
  postContent: string,
  topic: string,
  existingComments: ExistingComment[],
  viewerComment: string,
): RankedContact[] {
  const mentionedIds = extractMentionedPersonaIds([
    postContent,
    viewerComment,
    topic,
  ]);
  const threadParticipantIds = new Set(
    existingComments
      .map((comment) => comment.authorId)
      .filter((commentAuthorId) => commentAuthorId !== "viewer"),
  );
  const corpus = `${postContent}\n${topic}\n${viewerComment}`.trim();

  return allContactsFor(authorId)
    .map((contact) => {
      const reasonCodes: string[] = [];
      let score = 1;

      const overlap = keywordOverlapScore(corpus, contact.triggerKeywords);
      if (overlap > 0) {
        score += overlap * 3;
        reasonCodes.push("topic_match");
      }

      if (mentionedIds.has(contact.id)) {
        score += 5;
        reasonCodes.push("mention_hit");
      }

      if (threadParticipantIds.has(contact.id)) {
        score += 2;
        reasonCodes.push("thread_participant");
      }

      if (
        contact.domains.some((domain) =>
          topic.toLowerCase().includes(domain.toLowerCase())
        )
      ) {
        score += 2;
        reasonCodes.push("domain_fit");
      }

      reasonCodes.push("close_tie");

      return {
        ...contact,
        score,
        reasonCodes: [...new Set(reasonCodes)],
      };
    })
    .sort((left, right) =>
      right.score - left.score ||
      left.displayName.localeCompare(right.displayName)
    );
}

export function pickSeedCommenters(ranked: RankedContact[]): RankedContact[] {
  const strongMatches = ranked.filter((contact) => contact.score >= 3);
  return strongMatches.length === 0
    ? ranked.slice(0, 1)
    : strongMatches.slice(0, 2);
}

export function fallbackSeedCommenters(authorId: string): RankedContact[] {
  const persona = resolvePersonaById(authorId);
  if (!persona) return [];

  return persona.socialCircleIds
    .map((contactId) => resolvePersonaById(contactId))
    .filter((contact): contact is NonNullable<typeof contact> =>
      contact !== null
    )
    .slice(0, 2)
    .map((contact) => ({
      id: contact.personaId,
      username: contact.personaId,
      displayName: contact.displayName,
      stance: contact.stance,
      domains: contact.domains,
      triggerKeywords: contact.triggerKeywords,
      relationshipHint: relationshipHint(authorId, contact.personaId),
      score: 1,
      reasonCodes: ["fallback_circle"],
    }));
}

export function pickReplyParticipants(
  authorId: string,
  ranked: RankedContact[],
  viewerComment: string,
): RankedContact[] {
  const mentionedIds = extractMentionedPersonaIds([viewerComment]);
  return ranked
    .filter((contact) =>
      contact.id !== authorId && mentionedIds.has(contact.id)
    )
    .slice(0, 1);
}
