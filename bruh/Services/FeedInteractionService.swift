import Foundation
import SwiftData

struct FeedInteractionState {
    let likes: [FeedLike]
    let comments: [FeedComment]
}

struct FeedInteractionTarget {
    let id: String
    let personaId: String
    let postContent: String
    let topic: String?
}

private enum FeedInteractionGenerationMode: String {
    case seed
    case viewer
    case reply
}

private enum FeedInteractionGenerationStrategy {
    static let localPersonaV1 = "local_persona_v1"
    static let version = 1
}

private struct LocalFeedLikeDraft {
    let id: String
    let postId: String
    let authorId: String
    let authorDisplayName: String
    let reasonCode: String
    let generationMode: FeedInteractionGenerationMode
    let createdAt: Date
}

private struct LocalFeedCommentDraft {
    let id: String
    let postId: String
    let authorId: String
    let authorDisplayName: String
    let content: String
    let reasonCode: String
    let generationMode: FeedInteractionGenerationMode
    let inReplyToCommentId: String?
    let createdAt: Date
}

private enum FeedLocalInteractionGenerator {
    private struct RankedPersona {
        let entry: PersonaCatalogEntry
        let score: Int
        let reasonCode: String
        let tieBreaker: UInt32
    }

    static func seedInteractions(
        postId: String,
        personaId: String,
        postContent: String,
        topic: String?
    ) -> (likes: [LocalFeedLikeDraft], comments: [LocalFeedCommentDraft]) {
        let author = PersonaCatalog.entry(for: personaId)
        let ranked = rankedCandidates(postId: postId, authorId: personaId, postContent: postContent, topic: topic)
        guard !ranked.isEmpty else {
            return ([], [])
        }

        let baseDate = Date()
        let likeCount = min(ranked.count, max(1, Int(stableHash("\(postId)|likes") % 3) + 1))
        let likes = ranked.prefix(likeCount).enumerated().map { index, rankedPersona in
            LocalFeedLikeDraft(
                id: "like-\(postId)-\(rankedPersona.entry.id)",
                postId: postId,
                authorId: rankedPersona.entry.id,
                authorDisplayName: rankedPersona.entry.displayName,
                reasonCode: rankedPersona.reasonCode,
                generationMode: .seed,
                createdAt: baseDate.addingTimeInterval(Double(index))
            )
        }

        let commentCandidates = Array(ranked.filter { $0.score >= 3 }.prefix(2))
        let finalCommenters = commentCandidates.isEmpty ? Array(ranked.prefix(1)) : commentCandidates
        let comments = finalCommenters.enumerated().map { index, rankedPersona in
            LocalFeedCommentDraft(
                id: "comment-\(postId)-seed-\(rankedPersona.entry.id)",
                postId: postId,
                authorId: rankedPersona.entry.id,
                authorDisplayName: rankedPersona.entry.displayName,
                content: seedComment(
                    authorId: rankedPersona.entry.id,
                    postAuthorDisplayName: author?.displayName ?? "",
                    postContent: postContent,
                    topic: topic,
                    variantSeed: "\(postId)|comment|\(rankedPersona.entry.id)"
                ),
                reasonCode: rankedPersona.reasonCode,
                generationMode: .seed,
                inReplyToCommentId: nil,
                createdAt: baseDate.addingTimeInterval(Double(index + 1))
            )
        }

        return (likes, comments)
    }

    static func reply(
        postId: String,
        personaId: String,
        postContent: String,
        topic: String?,
        viewerCommentId: String,
        viewerComment: String,
        replyTargetAuthorId: String?
    ) -> LocalFeedCommentDraft {
        let responderId = resolvedResponderId(postAuthorId: personaId, replyTargetAuthorId: replyTargetAuthorId)
        let responderName = PersonaCatalog.entry(for: responderId)?.displayName ?? responderId

        return LocalFeedCommentDraft(
            id: "comment-\(postId)-reply-\(responderId)-\(viewerCommentId)",
            postId: postId,
            authorId: responderId,
            authorDisplayName: responderName,
            content: replyComment(
                authorId: responderId,
                viewerComment: viewerComment,
                postContent: postContent,
                topic: topic
            ),
            reasonCode: responderId == personaId ? "author_reply" : "thread_reply",
            generationMode: .reply,
            inReplyToCommentId: viewerCommentId,
            createdAt: .now.addingTimeInterval(1)
        )
    }

    private static func resolvedResponderId(postAuthorId: String, replyTargetAuthorId: String?) -> String {
        guard let replyTargetAuthorId, !replyTargetAuthorId.isEmpty, replyTargetAuthorId != "viewer" else {
            return postAuthorId
        }
        return replyTargetAuthorId
    }

    private static func rankedCandidates(
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

    private static func mentionedPersonaIds(in corpus: String) -> Set<String> {
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

    private static func seedComment(
        authorId: String,
        postAuthorDisplayName: String,
        postContent: String,
        topic: String?,
        variantSeed: String
    ) -> String {
        let english = isLikelyEnglishText(postContent)
        let cue = cueText(from: postContent, topic: topic, english: english)
        let variant = Int(stableHash(variantSeed) % 3)

        switch authorId {
        case "musk":
            return english
                ? englishVariant(variant, options: [
                    "\(cueOrFallback(cue, fallback: "This")) is mostly execution.",
                    "The real constraint matters more than the noise.",
                    "Interesting signal. I'd still watch the bottleneck.",
                ])
                : chineseVariant(variant, options: [
                    "\(cueOrFallback(cue, fallback: "这事"))最后还是看 execution。",
                    "真正该看的还是约束和瓶颈。",
                    "有点意思，但先别被情绪带着走。",
                ])
        case "trump":
            return english
                ? englishVariant(variant, options: [
                    "Strong post. People can feel the momentum.",
                    "\(cueOrFallback(cue, fallback: "This")) is a big signal.",
                    "A lot of people are thinking the same thing.",
                ])
                : chineseVariant(variant, options: [
                    "这条发得很强，气势是有的。",
                    "\(cueOrFallback(cue, fallback: "这事"))本身就是个很强的信号。",
                    "很多人其实都在这么想，只是没说出来。",
                ])
        case "sam_altman":
            return english
                ? englishVariant(variant, options: [
                    "The useful question is what this unlocks next.",
                    "\(cueOrFallback(cue, fallback: "This")) matters if builders can ship more from it.",
                    "The signal is real if it changes what people can do next.",
                ])
                : chineseVariant(variant, options: [
                    "关键还是它接下来能 unlock 什么。",
                    "\(cueOrFallback(cue, fallback: "这件事"))有意义，前提是它真的改变下一步能做什么。",
                    "如果这会改变大家接下来能做成的东西，那信号就是真的。",
                ])
        case "kobe_bryant":
            return english
                ? englishVariant(variant, options: [
                    "Pressure only shows whether the work was really there.",
                    "\(cueOrFallback(cue, fallback: "This")) comes down to standards and execution.",
                    "The part that matters is what they were prepared to do when it got hard.",
                ])
                : chineseVariant(variant, options: [
                    "压力只会暴露训练是不是真的到位。",
                    "\(cueOrFallback(cue, fallback: "这件事"))最后还是标准和执行的问题。",
                    "真正值得看的是，难的时候他们有没有准备好。",
                ])
        default:
            let trimmedAuthorName = postAuthorDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
            return english
                ? englishVariant(variant, options: [
                    "Interesting angle.",
                    "\(cueOrFallback(cue, fallback: trimmedAuthorName.isEmpty ? "This" : trimmedAuthorName)) is worth watching.",
                    "There is a real signal here.",
                ])
                : chineseVariant(variant, options: [
                    "这条角度挺对。",
                    "\(cueOrFallback(cue, fallback: trimmedAuthorName.isEmpty ? "这件事" : trimmedAuthorName))是值得继续看的。",
                    "这里面确实有信号。",
                ])
        }
    }

    private static func replyComment(
        authorId: String,
        viewerComment: String,
        postContent: String,
        topic: String?
    ) -> String {
        let english = isLikelyEnglishText(viewerComment)
        let lowSignal = isLowSignal(viewerComment)
        let cue = cueText(from: postContent, topic: topic, english: english)

        switch authorId {
        case "musk":
            if english {
                return lowSignal ? "Say the concrete bottleneck." : "I saw it. Tell me the actual bottleneck you care about."
            }
            return lowSignal ? "直接说你关心的瓶颈。" : "我看到了，直接说你真正在追问哪个瓶颈。"
        case "trump":
            if english {
                return lowSignal ? "Say it clearly." : "I saw it. Say the strongest version of your point."
            }
            return lowSignal ? "直接说清楚。" : "我看到了，你直接把你最想说的那一句讲出来。"
        case "sam_altman":
            if english {
                return lowSignal ? "Give me the concrete version." : "I saw it. What is the concrete unlock here?"
            }
            return lowSignal ? "先说具体一点。" : "我看到了，你先说这里最具体的 unlock 是什么。"
        case "kobe_bryant":
            if english {
                return lowSignal ? "Say the standard." : "I saw it. Tell me where the standard held or broke."
            }
            return lowSignal ? "直接说标准。" : "我看到了，你直接说这里到底是标准没守住，还是执行没到位。"
        default:
            if english {
                return lowSignal ? "Say a little more." : "I saw it. Say what part of this you want to discuss."
            }
            if !cue.isEmpty {
                return "我看到了，你是想聊 \(cue) 的哪一层？"
            }
            return lowSignal ? "说具体一点。" : "我看到了，直接说你想讨论哪一层。"
        }
    }

    private static func cueText(from postContent: String, topic: String?, english: Bool) -> String {
        let trimmedTopic = topic?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmedTopic.isEmpty {
            return trimmedTopic
        }

        let trimmedContent = postContent.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedContent.isEmpty else { return "" }

        if english {
            let words = trimmedContent
                .split(whereSeparator: \.isWhitespace)
                .prefix(5)
                .map(String.init)
            return words.joined(separator: " ")
        }

        let stripped = trimmedContent
            .replacingOccurrences(of: "\n", with: " ")
            .split(whereSeparator: { "，。！？；,.!?;".contains($0) })
            .first
            .map(String.init)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return String(stripped.prefix(12))
    }

    private static func cueOrFallback(_ cue: String, fallback: String) -> String {
        cue.isEmpty ? fallback : cue
    }

    private static func englishVariant(_ variant: Int, options: [String]) -> String {
        options[clampedVariant(variant, count: options.count)]
    }

    private static func chineseVariant(_ variant: Int, options: [String]) -> String {
        options[clampedVariant(variant, count: options.count)]
    }

    private static func clampedVariant(_ variant: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        return max(0, min(variant, count - 1))
    }

    private static func isLikelyEnglishText(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        if trimmed.range(of: #"[一-龥]"#, options: .regularExpression) != nil {
            return false
        }
        return trimmed.range(of: #"[A-Za-z]"#, options: .regularExpression) != nil
    }

    private static func isLowSignal(_ text: String) -> Bool {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return true }
        if normalized.count <= 4 {
            return true
        }

        return [
            "hi", "hey", "hello", "ok", "okay", "cool", "nice", "wow", "lol",
            "哈", "哈哈", "嗯", "哦", "在吗",
        ].contains(normalized)
    }

    private static func stableHash(_ input: String) -> UInt32 {
        var hash: UInt32 = 2166136261
        for scalar in input.unicodeScalars {
            hash ^= UInt32(scalar.value)
            hash = hash &* 16777619
        }
        return hash
    }
}

@MainActor
final class FeedInteractionService {
    func loadInteractions(for target: FeedInteractionTarget, modelContext: ModelContext) async throws -> FeedInteractionState {
        try ensureSeededInteractions(for: target, modelContext: modelContext)
        return try interactionState(for: target.id, modelContext: modelContext)
    }

    func sendViewerComment(
        for target: FeedInteractionTarget,
        text: String,
        replyToCommentId: String? = nil,
        modelContext: ModelContext
    ) async throws -> FeedInteractionState {
        try ensureSeededInteractions(for: target, modelContext: modelContext)

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return try interactionState(for: target.id, modelContext: modelContext)
        }

        let existingComments = try fetchComments(for: target.id, modelContext: modelContext)
        let normalizedReplyToCommentId = normalizedReplyTargetId(replyToCommentId, comments: existingComments)
        let viewerCommentId = "viewer-\(UUID().uuidString)"
        let viewerComment = FeedComment(
            id: viewerCommentId,
            postId: target.id,
            authorId: "viewer",
            authorDisplayName: "你",
            content: trimmed,
            reasonCode: "viewer_input",
            generationMode: FeedInteractionGenerationMode.viewer.rawValue,
            inReplyToCommentId: normalizedReplyToCommentId,
            isViewer: true,
            createdAt: .now,
            deliveryState: "sent"
        )
        modelContext.insert(viewerComment)

        let responderId = primaryResponderId(
            for: normalizedReplyToCommentId,
            comments: existingComments,
            defaultAuthorId: target.personaId
        )
        let personaReply = FeedLocalInteractionGenerator.reply(
            postId: target.id,
            personaId: target.personaId,
            postContent: target.postContent,
            topic: target.topic,
            viewerCommentId: viewerCommentId,
            viewerComment: trimmed,
            replyTargetAuthorId: responderId
        )
        upsert(commentDraft: personaReply, modelContext: modelContext)

        try saveIfNeeded(modelContext: modelContext)
        return try interactionState(for: target.id, modelContext: modelContext)
    }

    func setViewerLike(
        for target: FeedInteractionTarget,
        isLiked: Bool,
        modelContext: ModelContext
    ) async throws -> FeedInteractionState {
        try ensureSeededInteractions(for: target, modelContext: modelContext)

        let viewerLikeId = "like-\(target.id)-viewer"
        if isLiked {
            upsert(
                likeDraft: LocalFeedLikeDraft(
                    id: viewerLikeId,
                    postId: target.id,
                    authorId: "viewer",
                    authorDisplayName: "你",
                    reasonCode: "viewer_like",
                    generationMode: .viewer,
                    createdAt: .now
                ),
                modelContext: modelContext
            )
        } else if let existing = try fetchLike(id: viewerLikeId, modelContext: modelContext) {
            modelContext.delete(existing)
        }

        try saveIfNeeded(modelContext: modelContext)
        return try interactionState(for: target.id, modelContext: modelContext)
    }

    func interactionState(for postId: String, modelContext: ModelContext) throws -> FeedInteractionState {
        FeedInteractionState(
            likes: try fetchLikes(for: postId, modelContext: modelContext),
            comments: try fetchComments(for: postId, modelContext: modelContext)
        )
    }

    private func ensureSeededInteractions(for target: FeedInteractionTarget, modelContext: ModelContext) throws {
        if try fetchSeedState(for: target.id, modelContext: modelContext) != nil {
            return
        }

        let existingLikes = try fetchLikes(for: target.id, modelContext: modelContext)
        let existingComments = try fetchComments(for: target.id, modelContext: modelContext)
        if !existingLikes.isEmpty || !existingComments.isEmpty {
            upsertSeedState(for: target.id, modelContext: modelContext)
            try saveIfNeeded(modelContext: modelContext)
            return
        }

        let seeded = FeedLocalInteractionGenerator.seedInteractions(
            postId: target.id,
            personaId: target.personaId,
            postContent: target.postContent,
            topic: target.topic
        )

        for like in seeded.likes {
            upsert(likeDraft: like, modelContext: modelContext)
        }

        for comment in seeded.comments {
            upsert(commentDraft: comment, modelContext: modelContext)
        }

        upsertSeedState(for: target.id, modelContext: modelContext)
        try saveIfNeeded(modelContext: modelContext)
    }

    private func fetchLikes(for postId: String, modelContext: ModelContext) throws -> [FeedLike] {
        let targetPostId = postId
        let descriptor = FetchDescriptor<FeedLike>(
            predicate: #Predicate { $0.postId == targetPostId },
            sortBy: [SortDescriptor(\FeedLike.createdAt, order: .forward)]
        )
        return try modelContext.fetch(descriptor)
    }

    private func fetchComments(for postId: String, modelContext: ModelContext) throws -> [FeedComment] {
        let targetPostId = postId
        let descriptor = FetchDescriptor<FeedComment>(
            predicate: #Predicate { $0.postId == targetPostId },
            sortBy: [SortDescriptor(\FeedComment.createdAt, order: .forward)]
        )
        return try modelContext.fetch(descriptor)
    }

    private func fetchLike(id: String, modelContext: ModelContext) throws -> FeedLike? {
        let targetId = id
        var descriptor = FetchDescriptor<FeedLike>(
            predicate: #Predicate { $0.id == targetId }
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    private func fetchComment(id: String, modelContext: ModelContext) throws -> FeedComment? {
        let targetId = id
        var descriptor = FetchDescriptor<FeedComment>(
            predicate: #Predicate { $0.id == targetId }
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    private func fetchSeedState(for postId: String, modelContext: ModelContext) throws -> FeedInteractionSeedState? {
        let targetPostId = postId
        var descriptor = FetchDescriptor<FeedInteractionSeedState>(
            predicate: #Predicate { $0.postId == targetPostId }
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    private func upsertSeedState(for postId: String, modelContext: ModelContext) {
        if let existing = try? fetchSeedState(for: postId, modelContext: modelContext) {
            existing.generationVersion = FeedInteractionGenerationStrategy.version
            existing.strategy = FeedInteractionGenerationStrategy.localPersonaV1
            existing.updatedAt = .now
        } else {
            modelContext.insert(
                FeedInteractionSeedState(
                    postId: postId,
                    generationVersion: FeedInteractionGenerationStrategy.version,
                    strategy: FeedInteractionGenerationStrategy.localPersonaV1
                )
            )
        }
    }

    private func upsert(likeDraft: LocalFeedLikeDraft, modelContext: ModelContext) {
        if let existing = try? fetchLike(id: likeDraft.id, modelContext: modelContext) {
            existing.authorDisplayName = likeDraft.authorDisplayName
            existing.reasonCode = likeDraft.reasonCode
            existing.generationMode = likeDraft.generationMode.rawValue
            existing.createdAt = likeDraft.createdAt
            existing.isViewer = likeDraft.authorId == "viewer"
            return
        }

        modelContext.insert(
            FeedLike(
                id: likeDraft.id,
                postId: likeDraft.postId,
                authorId: likeDraft.authorId,
                authorDisplayName: likeDraft.authorDisplayName,
                reasonCode: likeDraft.reasonCode,
                generationMode: likeDraft.generationMode.rawValue,
                createdAt: likeDraft.createdAt,
                isViewer: likeDraft.authorId == "viewer"
            )
        )
    }

    private func upsert(commentDraft: LocalFeedCommentDraft, modelContext: ModelContext) {
        if let existing = try? fetchComment(id: commentDraft.id, modelContext: modelContext) {
            existing.authorDisplayName = commentDraft.authorDisplayName
            existing.content = commentDraft.content
            existing.reasonCode = commentDraft.reasonCode
            existing.generationMode = commentDraft.generationMode.rawValue
            existing.inReplyToCommentId = commentDraft.inReplyToCommentId
            existing.createdAt = commentDraft.createdAt
            existing.deliveryState = "sent"
            existing.isViewer = commentDraft.authorId == "viewer"
            return
        }

        modelContext.insert(
            FeedComment(
                id: commentDraft.id,
                postId: commentDraft.postId,
                authorId: commentDraft.authorId,
                authorDisplayName: commentDraft.authorDisplayName,
                content: commentDraft.content,
                reasonCode: commentDraft.reasonCode,
                generationMode: commentDraft.generationMode.rawValue,
                inReplyToCommentId: commentDraft.inReplyToCommentId,
                isViewer: commentDraft.authorId == "viewer",
                createdAt: commentDraft.createdAt,
                deliveryState: "sent"
            )
        )
    }

    private func normalizedReplyTargetId(_ replyToCommentId: String?, comments: [FeedComment]) -> String? {
        guard let trimmed = replyToCommentId?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }

        return comments.contains(where: { $0.id == trimmed }) ? trimmed : nil
    }

    private func primaryResponderId(
        for replyToCommentId: String?,
        comments: [FeedComment],
        defaultAuthorId: String
    ) -> String {
        guard let replyToCommentId else { return defaultAuthorId }

        let commentsById = Dictionary(uniqueKeysWithValues: comments.map { ($0.id, $0) })
        var currentCommentId: String? = replyToCommentId
        var visited = Set<String>()

        while let commentId = currentCommentId, !visited.contains(commentId) {
            guard let comment = commentsById[commentId] else {
                break
            }

            if !comment.isViewer {
                return comment.authorId
            }

            visited.insert(commentId)
            currentCommentId = comment.inReplyToCommentId
        }

        return defaultAuthorId
    }

    private func saveIfNeeded(modelContext: ModelContext) throws {
        if modelContext.hasChanges {
            try modelContext.save()
        }
    }
}
