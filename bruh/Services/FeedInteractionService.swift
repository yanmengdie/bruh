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

@MainActor
final class FeedInteractionService {
    private let api: APIClient
    private let demoPinnedPrefix = "demo_moments_"

    init(api: APIClient = APIClient()) {
        self.api = api
    }

    func loadInteractions(for target: FeedInteractionTarget, modelContext: ModelContext) async throws -> FeedInteractionState {
        if let pinnedPostId = canonicalPinnedPostId(for: target.id) {
            return try interactionState(for: pinnedPostId, modelContext: modelContext)
        }

        let reply = try await api.generatePostInteractions(
            postId: target.id,
            personaId: target.personaId,
            postContent: target.postContent,
            topic: target.topic
        )

        try replaceState(with: reply, modelContext: modelContext)
        return try interactionState(for: target.id, modelContext: modelContext)
    }

    func sendViewerComment(
        for target: FeedInteractionTarget,
        text: String,
        modelContext: ModelContext
    ) async throws -> FeedInteractionState {
        if let pinnedPostId = canonicalPinnedPostId(for: target.id) {
            return try interactionState(for: pinnedPostId, modelContext: modelContext)
        }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return try interactionState(for: target.id, modelContext: modelContext)
        }

        let commentId = "viewer-\(UUID().uuidString)"
        let reply = try await api.generatePostInteractions(
            postId: target.id,
            personaId: target.personaId,
            postContent: target.postContent,
            topic: target.topic,
            viewerComment: trimmed,
            viewerCommentId: commentId
        )

        try replaceState(with: reply, modelContext: modelContext)
        return try interactionState(for: target.id, modelContext: modelContext)
    }

    func setViewerLike(
        for target: FeedInteractionTarget,
        isLiked: Bool,
        modelContext: ModelContext
    ) async throws -> FeedInteractionState {
        if let pinnedPostId = canonicalPinnedPostId(for: target.id) {
            return try interactionState(for: pinnedPostId, modelContext: modelContext)
        }

        let reply = try await api.generatePostInteractions(
            postId: target.id,
            personaId: target.personaId,
            postContent: target.postContent,
            topic: target.topic,
            viewerLikeAction: isLiked ? "like" : "unlike"
        )

        try replaceState(with: reply, modelContext: modelContext)
        return try interactionState(for: target.id, modelContext: modelContext)
    }

    func interactionState(for postId: String, modelContext: ModelContext) throws -> FeedInteractionState {
        let resolvedPostId = canonicalPinnedPostId(for: postId) ?? postId
        return FeedInteractionState(
            likes: try fetchLikes(for: resolvedPostId, modelContext: modelContext),
            comments: try fetchComments(for: resolvedPostId, modelContext: modelContext)
        )
    }

    private func canonicalPinnedPostId(for postId: String) -> String? {
        if postId.hasPrefix(demoPinnedPrefix) {
            return postId
        }
        let eventPrefix = "event:feed:\(demoPinnedPrefix)"
        if postId.hasPrefix(eventPrefix) {
            return String(postId.dropFirst("event:feed:".count))
        }
        let deliveryPrefix = "delivery:feed:\(demoPinnedPrefix)"
        if postId.hasPrefix(deliveryPrefix) {
            return String(postId.dropFirst("delivery:feed:".count))
        }
        return nil
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

    private func replaceState(with reply: FeedInteractionReplyDTO, modelContext: ModelContext) throws {
        let remoteLikeIds = Set(reply.likes.map(\.id))
        for like in try fetchLikes(for: reply.postId, modelContext: modelContext) where !remoteLikeIds.contains(like.id) {
            modelContext.delete(like)
        }

        let remoteCommentIds = Set(reply.comments.map(\.id))
        for comment in try fetchComments(for: reply.postId, modelContext: modelContext) where !remoteCommentIds.contains(comment.id) {
            modelContext.delete(comment)
        }

        for like in reply.likes {
            let targetId = like.id
            var descriptor = FetchDescriptor<FeedLike>(
                predicate: #Predicate { $0.id == targetId }
            )
            descriptor.fetchLimit = 1

            if let existing = try modelContext.fetch(descriptor).first {
                existing.authorDisplayName = like.authorDisplayName
                existing.reasonCode = like.reasonCode
                existing.createdAt = like.createdAt
                existing.isViewer = like.authorId == "viewer"
            } else {
                modelContext.insert(
                    FeedLike(
                        id: like.id,
                        postId: like.postId,
                        authorId: like.authorId,
                        authorDisplayName: like.authorDisplayName,
                        reasonCode: like.reasonCode,
                        createdAt: like.createdAt,
                        isViewer: like.authorId == "viewer"
                    )
                )
            }
        }

        for comment in reply.comments {
            let targetId = comment.id
            var descriptor = FetchDescriptor<FeedComment>(
                predicate: #Predicate { $0.id == targetId }
            )
            descriptor.fetchLimit = 1

            if let existing = try modelContext.fetch(descriptor).first {
                existing.content = comment.content
                existing.reasonCode = comment.reasonCode
                existing.inReplyToCommentId = comment.inReplyToCommentId
                existing.createdAt = comment.createdAt
                existing.deliveryState = "sent"
                existing.isViewer = comment.isViewer
            } else {
                modelContext.insert(
                    FeedComment(
                        id: comment.id,
                        postId: comment.postId,
                        authorId: comment.authorId,
                        authorDisplayName: comment.authorDisplayName,
                        content: comment.content,
                        reasonCode: comment.reasonCode,
                        inReplyToCommentId: comment.inReplyToCommentId,
                        isViewer: comment.isViewer,
                        createdAt: comment.createdAt,
                        deliveryState: "sent"
                    )
                )
            }
        }

        if modelContext.hasChanges {
            try modelContext.save()
        }
    }
}
