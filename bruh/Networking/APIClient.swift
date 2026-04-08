import Foundation

enum NetworkError: LocalizedError {
    case invalidURL
    case httpError(Int)
    case decodingError
    case noData

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid URL"
        case .httpError(let code): return "HTTP error \(code)"
        case .decodingError: return "Failed to decode response"
        case .noData: return "No data received"
        }
    }
}

actor APIClient {
    private let baseURL: String
    private let anonKey: String
    private let session: URLSession

    init(
        baseURL: String = "https://mrxctelezutprdeemqla.supabase.co/functions/v1",
        anonKey: String = "sb_publishable_ry_i_qMeMDzxeE7qhSl1UA_XcAwgQL1"
    ) {
        self.baseURL = baseURL
        self.anonKey = anonKey
        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        self.session = URLSession(configuration: configuration)
    }

    /// Fetch posts newer than `since` (ISO8601).
    func fetchFeed(since: Date? = nil, limit: Int = 20) async throws -> [PostDTO] {
        var components = URLComponents(string: "\(baseURL)/feed")!
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "limit", value: "\(limit)"),
            // Avoid stale timeline payloads from URLSession/HTTP caches for feed refresh.
            URLQueryItem(name: "_ts", value: "\(Int(Date().timeIntervalSince1970))")
        ]
        if let since {
            let iso = ISO8601DateFormatter()
            queryItems.append(URLQueryItem(name: "since", value: iso.string(from: since)))
        }
        components.queryItems = queryItems

        guard let url = components.url else { throw NetworkError.invalidURL }

        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(anonKey)", forHTTPHeaderField: "Authorization")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        request.setValue("no-cache", forHTTPHeaderField: "Pragma")

        let (data, response) = try await session.data(for: request)

        guard let http = response as? HTTPURLResponse else { throw NetworkError.noData }
        guard (200...299).contains(http.statusCode) else { throw NetworkError.httpError(http.statusCode) }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            return try decoder.decode([PostDTO].self, from: data)
        } catch {
            throw NetworkError.decodingError
        }
    }

    func sendMessage(
        personaId: String,
        userMessage: String,
        conversation: [MessageTurnDTO],
        userInterests: [String],
        requestImage: Bool = false
    ) async throws -> MessageReplyDTO {
        guard let url = URL(string: "\(baseURL)/generate-message") else {
            throw NetworkError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(anonKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            SendMessageRequestDTO(
                personaId: personaId,
                userMessage: userMessage,
                conversation: conversation,
                userInterests: userInterests,
                requestImage: requestImage
            )
        )

        let (data, response) = try await session.data(for: request)

        guard let http = response as? HTTPURLResponse else { throw NetworkError.noData }
        guard (200...299).contains(http.statusCode) else { throw NetworkError.httpError(http.statusCode) }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            return try decoder.decode(MessageReplyDTO.self, from: data)
        } catch {
            throw NetworkError.decodingError
        }
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
        request.httpBody = try JSONEncoder().encode(
            MessageStarterRequestDTO(userInterests: userInterests)
        )

        let (data, response) = try await session.data(for: request)

        guard let http = response as? HTTPURLResponse else { throw NetworkError.noData }
        guard (200...299).contains(http.statusCode) else { throw NetworkError.httpError(http.statusCode) }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            return try decoder.decode(MessageStarterReplyDTO.self, from: data)
        } catch {
            throw NetworkError.decodingError
        }
    }

    func generatePostInteractions(
        postId: String,
        personaId: String,
        postContent: String,
        topic: String?,
        viewerComment: String? = nil,
        viewerCommentId: String? = nil,
        viewerLikeAction: String? = nil
    ) async throws -> FeedInteractionReplyDTO {
        guard let url = URL(string: "\(baseURL)/generate-post-interactions") else {
            throw NetworkError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(anonKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            FeedInteractionRequestDTO(
                postId: postId,
                personaId: personaId,
                postContent: postContent,
                topic: topic,
                viewerComment: viewerComment,
                viewerCommentId: viewerCommentId,
                viewerLikeAction: viewerLikeAction
            )
        )

        let (data, response) = try await session.data(for: request)

        guard let http = response as? HTTPURLResponse else { throw NetworkError.noData }
        guard (200...299).contains(http.statusCode) else { throw NetworkError.httpError(http.statusCode) }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            return try decoder.decode(FeedInteractionReplyDTO.self, from: data)
        } catch {
            throw NetworkError.decodingError
        }
    }
}

// MARK: - DTO

struct PostDTO: Codable, Identifiable {
    let id: String
    let personaId: String
    let content: String
    let sourceType: String
    let sourceUrl: String?
    let topic: String?
    let importanceScore: Double
    let mediaUrls: [String]
    let videoUrl: String?
    let publishedAt: Date
}

struct MessageTurnDTO: Codable {
    let role: String
    let content: String
}

struct SendMessageRequestDTO: Codable {
    let personaId: String
    let userMessage: String
    let conversation: [MessageTurnDTO]
    let userInterests: [String]
    let requestImage: Bool
}

struct MessageReplyDTO: Codable, Identifiable {
    let id: String
    let personaId: String
    let content: String
    let imageUrl: String?
    let audioUrl: String?
    let audioDuration: TimeInterval?
    let voiceLabel: String?
    let audioOnly: Bool?
    let sourcePostIds: [String]
    let generatedAt: Date
}

struct FeedCommentTurnDTO: Codable {
    let id: String
    let authorId: String
    let authorDisplayName: String
    let content: String
    let isViewer: Bool
    let inReplyToCommentId: String?
}

struct FeedInteractionRequestDTO: Codable {
    let postId: String
    let personaId: String
    let postContent: String
    let topic: String?
    let viewerComment: String?
    let viewerCommentId: String?
    let viewerLikeAction: String?
}

struct FeedInteractionLikeDTO: Codable, Identifiable {
    let id: String
    let postId: String
    let authorId: String
    let authorDisplayName: String
    let reasonCode: String
    let createdAt: Date
}

struct FeedInteractionCommentDTO: Codable, Identifiable {
    let id: String
    let postId: String
    let authorId: String
    let authorDisplayName: String
    let content: String
    let reasonCode: String
    let inReplyToCommentId: String?
    let isViewer: Bool
    let createdAt: Date
}

struct FeedInteractionReplyDTO: Codable {
    let postId: String
    let likes: [FeedInteractionLikeDTO]
    let comments: [FeedInteractionCommentDTO]
    let generatedAt: Date
}

struct MessageStarterRequestDTO: Codable {
    let userInterests: [String]
}

struct MessageStarterDTO: Codable, Identifiable {
    let id: String
    let personaId: String
    let text: String
    let sourcePostIds: [String]
    let createdAt: Date
    let category: String
    let headline: String
    let articleUrl: String?
    let isGlobalTop: Bool
}

struct MessageStarterReplyDTO: Codable {
    let starters: [MessageStarterDTO]
    let topSummary: String
}
