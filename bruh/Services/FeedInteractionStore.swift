import Foundation
import SwiftData

enum FeedInteractionGenerationMode: String {
    case seed
    case viewer
    case reply
}

enum FeedInteractionGenerationStrategy {
    static let remoteDeepSeekV1 = "remote_deepseek_v1"
    static let localPersonaV1 = "local_persona_v1"
    static let version = 2
}

struct LocalFeedLikeDraft {
    let id: String
    let postId: String
    let authorId: String
    let authorDisplayName: String
    let reasonCode: String
    let generationMode: FeedInteractionGenerationMode
    let createdAt: Date
}

struct LocalFeedCommentDraft {
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

@MainActor
struct FeedInteractionStore {
    func fetchLikes(for postId: String, modelContext: ModelContext) throws -> [FeedLike] {
        let targetPostId = postId
        let descriptor = FetchDescriptor<FeedLike>(
            predicate: #Predicate { $0.postId == targetPostId },
            sortBy: [SortDescriptor(\FeedLike.createdAt, order: .forward)]
        )
        return try modelContext.fetch(descriptor)
    }

    func fetchComments(for postId: String, modelContext: ModelContext) throws -> [FeedComment] {
        let targetPostId = postId
        let descriptor = FetchDescriptor<FeedComment>(
            predicate: #Predicate { $0.postId == targetPostId },
            sortBy: [SortDescriptor(\FeedComment.createdAt, order: .forward)]
        )
        return try modelContext.fetch(descriptor)
    }

    func fetchLike(id: String, modelContext: ModelContext) throws -> FeedLike? {
        let targetId = id
        var descriptor = FetchDescriptor<FeedLike>(
            predicate: #Predicate { $0.id == targetId }
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    func fetchComment(id: String, modelContext: ModelContext) throws -> FeedComment? {
        let targetId = id
        var descriptor = FetchDescriptor<FeedComment>(
            predicate: #Predicate { $0.id == targetId }
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    func fetchSeedState(for postId: String, modelContext: ModelContext) throws -> FeedInteractionSeedState? {
        let targetPostId = postId
        var descriptor = FetchDescriptor<FeedInteractionSeedState>(
            predicate: #Predicate { $0.postId == targetPostId }
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    func upsertSeedState(for postId: String, strategy: String, modelContext: ModelContext) {
        if let existing = try? fetchSeedState(for: postId, modelContext: modelContext) {
            existing.generationVersion = FeedInteractionGenerationStrategy.version
            existing.strategy = strategy
            existing.updatedAt = .now
        } else {
            modelContext.insert(
                FeedInteractionSeedState(
                    postId: postId,
                    generationVersion: FeedInteractionGenerationStrategy.version,
                    strategy: strategy
                )
            )
        }
    }

    func upsert(likeDraft: LocalFeedLikeDraft, modelContext: ModelContext) {
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

    func upsert(commentDraft: LocalFeedCommentDraft, modelContext: ModelContext) {
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

    func saveIfNeeded(modelContext: ModelContext) throws {
        if modelContext.hasChanges {
            try modelContext.save()
        }
    }
}
