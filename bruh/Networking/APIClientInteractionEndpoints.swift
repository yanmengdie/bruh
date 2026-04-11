import Foundation

extension APIClient {
    func generateFeedInteractions(
        postId: String,
        personaId: String,
        postContent: String,
        topic: String?,
        viewerComment: String? = nil,
        viewerCommentId: String? = nil,
        replyToCommentId: String? = nil,
        replyTargetAuthorId: String? = nil,
        existingLikes: [FeedInteractionLikeRequestDTO],
        existingComments: [FeedInteractionCommentRequestDTO],
        persistRemote: Bool = false
    ) async throws -> FeedInteractionReplyDTO {
        guard let url = URL(string: "\(baseURL)/generate-post-interactions") else {
            throw NetworkError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(anonKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        APIContract.applyRequestHeaders(to: &request, contract: .generatePostInteractionsV1)
        request.httpBody = try JSONEncoder().encode(
            FeedInteractionRequestDTO(
                postId: postId,
                personaId: personaId,
                postContent: postContent,
                topic: topic,
                viewerComment: viewerComment,
                viewerCommentId: viewerCommentId,
                replyToCommentId: replyToCommentId,
                replyTargetAuthorId: replyTargetAuthorId,
                existingLikes: existingLikes,
                existingComments: existingComments,
                persistRemote: persistRemote
            )
        )

        return try await performDecodableRequest(
            request,
            as: FeedInteractionReplyDTO.self,
            retryProfile: .interactionGeneration,
            contract: .generatePostInteractionsV1
        )
    }
}
