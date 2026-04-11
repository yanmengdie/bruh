import Foundation

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
    let forceVoice: Bool
}

struct MessageReplyDTO: Decodable, Identifiable {
    let id: String
    let personaId: String
    let content: String
    let imageUrl: String?
    let sourceUrl: String?
    let audioUrl: String?
    let audioDuration: TimeInterval?
    let voiceLabel: String?
    let audioError: String?
    let audioOnly: Bool?
    let sourcePostIds: [String]
    let generatedAt: Date

    private enum CodingKeys: String, CodingKey {
        case id
        case personaId
        case persona_id
        case content
        case text
        case imageUrl
        case image_url
        case sourceUrl
        case source_url
        case audioUrl
        case audio_url
        case audioDuration
        case audio_duration
        case voiceLabel
        case voice_label
        case audioError
        case audio_error
        case audioOnly
        case audio_only
        case sourcePostIds
        case source_post_ids
        case generatedAt
        case generated_at
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        personaId = try container.decodeFirst(String.self, forKeys: [.personaId, .persona_id])
        content = try container.decodeFirst(String.self, forKeys: [.content, .text])
        imageUrl = RemoteMediaPolicy.normalizedAssetURLString(
            try container.decodeFirstIfPresent(String.self, forKeys: [.imageUrl, .image_url])
        )
        sourceUrl = RemoteMediaPolicy.normalizedSourceURLString(
            try container.decodeFirstIfPresent(String.self, forKeys: [.sourceUrl, .source_url])
        )
        audioUrl = RemoteMediaPolicy.normalizedAssetURLString(
            try container.decodeFirstIfPresent(String.self, forKeys: [.audioUrl, .audio_url])
        )
        audioDuration = try container.decodeFirstIfPresent(TimeInterval.self, forKeys: [.audioDuration, .audio_duration])
        voiceLabel = try container.decodeFirstIfPresent(String.self, forKeys: [.voiceLabel, .voice_label])
        audioError = try container.decodeFirstIfPresent(String.self, forKeys: [.audioError, .audio_error])
        audioOnly = try container.decodeFirstIfPresent(Bool.self, forKeys: [.audioOnly, .audio_only])
        sourcePostIds = try container.decodeFirstIfPresent([String].self, forKeys: [.sourcePostIds, .source_post_ids]) ?? []
        generatedAt = try container.decodeFirst(Date.self, forKeys: [.generatedAt, .generated_at])
    }
}

struct MessageStarterRequestDTO: Codable {
    let userInterests: [String]
}

struct MessageStarterDTO: Decodable, Identifiable {
    let id: String
    let personaId: String
    let text: String
    let imageUrl: String?
    let sourceUrl: String?
    let sourcePostIds: [String]
    let createdAt: Date
    let category: String
    let headline: String
    let isGlobalTop: Bool

    private enum CodingKeys: String, CodingKey {
        case id
        case personaId
        case persona_id
        case text
        case imageUrl
        case image_url
        case sourceUrl
        case source_url
        case articleUrl
        case article_url
        case sourcePostIds
        case source_post_ids
        case createdAt
        case created_at
        case category
        case headline
        case isGlobalTop
        case is_global_top
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        personaId = try container.decodeFirst(String.self, forKeys: [.personaId, .persona_id])
        text = try container.decode(String.self, forKey: .text)
        imageUrl = RemoteMediaPolicy.normalizedAssetURLString(
            try container.decodeFirstIfPresent(String.self, forKeys: [.imageUrl, .image_url])
        )
        sourceUrl = RemoteMediaPolicy.normalizedSourceURLString(
            try container.decodeFirstIfPresent(String.self, forKeys: [.sourceUrl, .source_url, .articleUrl, .article_url])
        )
        sourcePostIds = try container.decodeFirstIfPresent([String].self, forKeys: [.sourcePostIds, .source_post_ids]) ?? []
        createdAt = try container.decodeFirst(Date.self, forKeys: [.createdAt, .created_at])
        category = try container.decodeIfPresent(String.self, forKey: .category) ?? ""
        headline = try container.decodeIfPresent(String.self, forKey: .headline) ?? ""
        isGlobalTop = try container.decodeFirstIfPresent(Bool.self, forKeys: [.isGlobalTop, .is_global_top]) ?? false
    }
}

struct MessageStarterReplyDTO: Decodable {
    let starters: [MessageStarterDTO]
    let topSummary: String

    private enum CodingKeys: String, CodingKey {
        case starters
        case topSummary
        case top_summary
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        starters = try container.decodeIfPresent([MessageStarterDTO].self, forKey: .starters) ?? []
        topSummary = try container.decodeFirstIfPresent(String.self, forKeys: [.topSummary, .top_summary]) ?? ""
    }
}
