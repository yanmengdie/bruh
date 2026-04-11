import Foundation

extension APIClient {
    func sendMessage(
        personaId: String,
        userMessage: String,
        conversation: [MessageTurnDTO],
        userInterests: [String],
        requestImage: Bool = false,
        forceVoice: Bool = false
    ) async throws -> MessageReplyDTO {
        guard let url = URL(string: "\(baseURL)/generate-message") else {
            throw NetworkError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(anonKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        APIContract.applyRequestHeaders(to: &request, contract: .generateMessageV1)
        request.httpBody = try JSONEncoder().encode(
            SendMessageRequestDTO(
                personaId: personaId,
                userMessage: userMessage,
                conversation: conversation,
                userInterests: userInterests,
                requestImage: requestImage,
                forceVoice: forceVoice
            )
        )

        return try await performDecodableRequest(
            request,
            as: MessageReplyDTO.self,
            retryProfile: .messageSend,
            contract: .generateMessageV1
        )
    }

    func fetchMessageStarters(userInterests: [String]) async throws -> MessageStarterReplyDTO {
        guard let url = URL(string: "\(baseURL)/message-starters") else {
            throw NetworkError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 6
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(anonKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        APIContract.applyRequestHeaders(to: &request, contract: .messageStartersV1)
        request.httpBody = try JSONEncoder().encode(
            MessageStarterRequestDTO(userInterests: userInterests)
        )

        return try await performDecodableRequest(
            request,
            as: MessageStarterReplyDTO.self,
            retryProfile: .starterPrefetch,
            contract: .messageStartersV1
        )
    }
}
