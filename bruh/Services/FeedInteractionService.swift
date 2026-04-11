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
    private let apiClient: APIClient
    private let runtimeOptions: AppRuntimeOptions
    private let store: FeedInteractionStore

    init(
        apiClient: APIClient = APIClient(),
        runtimeOptions: AppRuntimeOptions = .current
    ) {
        self.apiClient = apiClient
        self.runtimeOptions = runtimeOptions
        self.store = FeedInteractionStore()
    }

    func loadInteractions(for target: FeedInteractionTarget, modelContext: ModelContext) async throws -> FeedInteractionState {
        try await ensureSeededInteractions(for: target, modelContext: modelContext)
        return try interactionState(for: target.id, modelContext: modelContext)
    }

    func sendViewerComment(
        for target: FeedInteractionTarget,
        text: String,
        replyToCommentId: String? = nil,
        modelContext: ModelContext
    ) async throws -> FeedInteractionState {
        try await ensureSeededInteractions(for: target, modelContext: modelContext)

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return try interactionState(for: target.id, modelContext: modelContext)
        }

        let existingComments = try store.fetchComments(for: target.id, modelContext: modelContext)
        let normalizedReplyToCommentId = store.normalizedReplyTargetId(replyToCommentId, comments: existingComments)
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
        try store.saveIfNeeded(modelContext: modelContext)

        let responderId = store.primaryResponderId(
            for: normalizedReplyToCommentId,
            comments: existingComments,
            defaultAuthorId: target.personaId
        )
        let likesAfterViewerComment = try store.fetchLikes(for: target.id, modelContext: modelContext)
        let commentsAfterViewerComment = try store.fetchComments(for: target.id, modelContext: modelContext)

        do {
            let remoteState = try await apiClient.generateFeedInteractions(
                postId: target.id,
                personaId: target.personaId,
                postContent: target.postContent,
                topic: target.topic,
                viewerComment: trimmed,
                viewerCommentId: viewerCommentId,
                replyToCommentId: normalizedReplyToCommentId,
                replyTargetAuthorId: responderId,
                existingLikes: store.requestLikes(from: likesAfterViewerComment),
                existingComments: store.requestComments(from: commentsAfterViewerComment),
                persistRemote: false
            )
            store.apply(remoteState: remoteState, modelContext: modelContext)
        } catch {
            if runtimeOptions.shouldUseLocalFeedInteractionFallbacks {
                let personaReply = FeedLocalInteractionGenerator.reply(
                    postId: target.id,
                    personaId: target.personaId,
                    postContent: target.postContent,
                    topic: target.topic,
                    viewerCommentId: viewerCommentId,
                    viewerComment: trimmed,
                    replyTargetAuthorId: responderId
                )
                store.upsert(commentDraft: personaReply, modelContext: modelContext)
            }
        }

        try store.saveIfNeeded(modelContext: modelContext)
        return try interactionState(for: target.id, modelContext: modelContext)
    }

    func setViewerLike(
        for target: FeedInteractionTarget,
        isLiked: Bool,
        modelContext: ModelContext
    ) async throws -> FeedInteractionState {
        try await ensureSeededInteractions(for: target, modelContext: modelContext)

        let viewerLikeId = "like-\(target.id)-viewer"
        if isLiked {
            store.upsert(
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
        } else if let existing = try store.fetchLike(id: viewerLikeId, modelContext: modelContext) {
            modelContext.delete(existing)
        }

        try store.saveIfNeeded(modelContext: modelContext)
        return try interactionState(for: target.id, modelContext: modelContext)
    }

    func interactionState(for postId: String, modelContext: ModelContext) throws -> FeedInteractionState {
        FeedInteractionState(
            likes: try store.fetchLikes(for: postId, modelContext: modelContext),
            comments: try store.fetchComments(for: postId, modelContext: modelContext)
        )
    }

    private func ensureSeededInteractions(for target: FeedInteractionTarget, modelContext: ModelContext) async throws {
        if let existingSeedState = try store.fetchSeedState(for: target.id, modelContext: modelContext),
           existingSeedState.generationVersion == FeedInteractionGenerationStrategy.version {
            return
        }

        let existingLikes = try store.fetchLikes(for: target.id, modelContext: modelContext)
        let existingComments = try store.fetchComments(for: target.id, modelContext: modelContext)
        if !existingLikes.isEmpty || !existingComments.isEmpty {
            store.upsertSeedState(
                for: target.id,
                strategy: store.hasViewerActivity(likes: existingLikes, comments: existingComments)
                    ? FeedInteractionGenerationStrategy.remoteDeepSeekV1
                    : FeedInteractionGenerationStrategy.localPersonaV1,
                modelContext: modelContext
            )
            try store.saveIfNeeded(modelContext: modelContext)
            return
        }

        do {
            let remoteState = try await apiClient.generateFeedInteractions(
                postId: target.id,
                personaId: target.personaId,
                postContent: target.postContent,
                topic: target.topic,
                existingLikes: [],
                existingComments: [],
                persistRemote: false
            )
            store.apply(remoteState: remoteState, modelContext: modelContext)
            store.upsertSeedState(
                for: target.id,
                strategy: FeedInteractionGenerationStrategy.remoteDeepSeekV1,
                modelContext: modelContext
            )
        } catch {
            guard runtimeOptions.shouldUseLocalFeedInteractionFallbacks else {
                return
            }

            let seeded = FeedLocalInteractionGenerator.seedInteractions(
                postId: target.id,
                personaId: target.personaId,
                postContent: target.postContent,
                topic: target.topic
            )

            for like in seeded.likes {
                store.upsert(likeDraft: like, modelContext: modelContext)
            }

            for comment in seeded.comments {
                store.upsert(commentDraft: comment, modelContext: modelContext)
            }

            store.upsertSeedState(
                for: target.id,
                strategy: FeedInteractionGenerationStrategy.localPersonaV1,
                modelContext: modelContext
            )
        }

        try store.saveIfNeeded(modelContext: modelContext)
    }
}
