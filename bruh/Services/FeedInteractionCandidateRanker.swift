import Foundation

extension FeedLocalInteractionGenerator {
    struct RankedPersona {
        let entry: PersonaCatalogEntry
        let score: Int
        let reasonCode: String
        let tieBreaker: UInt32
    }

    static func resolvedResponderId(postAuthorId: String, replyTargetAuthorId: String?) -> String {
        guard let replyTargetAuthorId, !replyTargetAuthorId.isEmpty, replyTargetAuthorId != "viewer" else {
            return postAuthorId
        }
        return replyTargetAuthorId
    }

    static func rankedCandidates(
        postId: String,
        authorId: String,
        postContent: String,
        topic: String?
    ) -> [RankedPersona] {
        let author = PersonaCatalog.entry(for: authorId)
        let corpus = [postContent, topic].compactMap { value in
            let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return trimmed.isEmpty ? nil : trimmed.lowercased()
        }.joined(separator: "\n")
        let mentionedIds = mentionedPersonaIds(in: corpus)
        let socialCircleIds = Set(author?.socialCircleIds ?? [])
        let topicLowercased = topic?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""

        let ranked = PersonaCatalog.all
            .filter { $0.id != authorId }
            .map { entry -> RankedPersona in
                var score = 0
                var reasonCode = "persona_fit"

                if socialCircleIds.contains(entry.id) {
                    score += 4
                    reasonCode = "social_circle"
                }

                if mentionedIds.contains(entry.id) {
                    score += 5
                    reasonCode = "mentioned"
                }

                let domainHits = entry.domains.filter { domain in
                    corpus.contains(domain.lowercased()) || topicLowercased.contains(domain.lowercased())
                }.count
                if domainHits > 0 {
                    score += min(domainHits, 2) * 2
                    if reasonCode == "persona_fit" {
                        reasonCode = "topic_match"
                    }
                }

                let triggerHits = entry.triggerKeywords.filter { keyword in
                    corpus.contains(keyword.lowercased())
                }.count
                if triggerHits > 0 {
                    score += min(triggerHits, 2)
                    if reasonCode == "persona_fit" {
                        reasonCode = "keyword_match"
                    }
                }

                return RankedPersona(
                    entry: entry,
                    score: score,
                    reasonCode: reasonCode,
                    tieBreaker: stableHash("\(postId)|\(entry.id)")
                )
            }
            .filter { $0.score > 0 }
            .sorted { left, right in
                if left.score != right.score {
                    return left.score > right.score
                }
                if left.tieBreaker != right.tieBreaker {
                    return left.tieBreaker < right.tieBreaker
                }
                return left.entry.displayName < right.entry.displayName
            }

        if !ranked.isEmpty {
            return ranked
        }

        let fallbackIds = Array((author?.socialCircleIds ?? []).prefix(3))
        if !fallbackIds.isEmpty {
            return fallbackIds.compactMap { fallbackId in
                guard let entry = PersonaCatalog.entry(for: fallbackId) else { return nil }
                return RankedPersona(
                    entry: entry,
                    score: 1,
                    reasonCode: "fallback_circle",
                    tieBreaker: stableHash("\(postId)|\(entry.id)")
                )
            }
        }

        return PersonaCatalog.all
            .filter { $0.id != authorId }
            .prefix(2)
            .map {
                RankedPersona(
                    entry: $0,
                    score: 1,
                    reasonCode: "fallback_persona",
                    tieBreaker: stableHash("\(postId)|\($0.id)")
                )
            }
    }

    static func mentionedPersonaIds(in corpus: String) -> Set<String> {
        let normalized = corpus.lowercased()
        var results = Set<String>()

        for entry in PersonaCatalog.all {
            let tokens = [
                entry.id.lowercased(),
                entry.displayName.lowercased(),
                entry.handle.lowercased(),
                "@\(entry.id.lowercased())",
                "@\(entry.handle.lowercased().replacingOccurrences(of: "@", with: ""))",
            ] + entry.aliases.map { $0.lowercased() } + entry.entityKeywords.map { $0.lowercased() }

            if tokens.contains(where: { !$0.isEmpty && normalized.contains($0) }) {
                results.insert(entry.id)
            }
        }

        return results
    }

    static func stableHash(_ input: String) -> UInt32 {
        var hash: UInt32 = 2166136261
        for scalar in input.unicodeScalars {
            hash ^= UInt32(scalar.value)
            hash = hash &* 16777619
        }
        return hash
    }
}
