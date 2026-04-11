import Foundation
import SwiftData

extension FeedInteractionStore {
    func normalizedReplyTargetId(_ replyToCommentId: String?, comments: [FeedComment]) -> String? {
        guard let trimmed = replyToCommentId?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }

        return comments.contains(where: { $0.id == trimmed }) ? trimmed : nil
    }

    func primaryResponderId(
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

    func requestLikes(from likes: [FeedLike]) -> [FeedInteractionLikeRequestDTO] {
        likes.map { like in
            FeedInteractionLikeRequestDTO(
                id: like.id,
                postId: like.postId,
                authorId: like.authorId,
                authorDisplayName: like.authorDisplayName,
                reasonCode: like.reasonCode,
                createdAt: like.createdAt
            )
        }
    }

    func requestComments(from comments: [FeedComment]) -> [FeedInteractionCommentRequestDTO] {
        comments.map { comment in
            FeedInteractionCommentRequestDTO(
                id: comment.id,
                postId: comment.postId,
                authorId: comment.authorId,
                authorDisplayName: comment.authorDisplayName,
                content: comment.content,
                reasonCode: comment.reasonCode,
                inReplyToCommentId: comment.inReplyToCommentId,
                isViewer: comment.isViewer,
                createdAt: comment.createdAt,
                generationMode: comment.generationMode
            )
        }
    }

    func apply(remoteState: FeedInteractionReplyDTO, modelContext: ModelContext) {
        for like in remoteState.likes {
            upsert(
                likeDraft: LocalFeedLikeDraft(
                    id: like.id,
                    postId: like.postId,
                    authorId: like.authorId,
                    authorDisplayName: like.authorDisplayName,
                    reasonCode: like.reasonCode,
                    generationMode: like.authorId == "viewer" ? .viewer : .seed,
                    createdAt: like.createdAt
                ),
                modelContext: modelContext
            )
        }

        for comment in remoteState.comments {
            let generationMode: FeedInteractionGenerationMode = comment.authorId == "viewer"
                ? .viewer
                : (comment.inReplyToCommentId == nil ? .seed : .reply)

            upsert(
                commentDraft: LocalFeedCommentDraft(
                    id: comment.id,
                    postId: comment.postId,
                    authorId: comment.authorId,
                    authorDisplayName: comment.authorDisplayName,
                    content: comment.content,
                    reasonCode: comment.reasonCode,
                    generationMode: generationMode,
                    inReplyToCommentId: comment.inReplyToCommentId,
                    createdAt: comment.createdAt
                ),
                modelContext: modelContext
            )
        }
    }

    func hasViewerActivity(likes: [FeedLike], comments: [FeedComment]) -> Bool {
        likes.contains(where: \.isViewer) || comments.contains(where: \.isViewer)
    }
}
