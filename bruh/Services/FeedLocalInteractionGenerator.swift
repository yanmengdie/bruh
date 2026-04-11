import Foundation

enum FeedLocalInteractionGenerator {
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
}
