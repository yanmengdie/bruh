import Foundation

struct PostDTO: Decodable, Identifiable {
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

    private enum CodingKeys: String, CodingKey {
        case id
        case personaId
        case persona_id
        case content
        case sourceType
        case source_type
        case sourceUrl
        case source_url
        case topic
        case importanceScore
        case importance_score
        case mediaUrls
        case media_urls
        case videoUrl
        case video_url
        case publishedAt
        case published_at
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        personaId = try container.decodeFirst(String.self, forKeys: [.personaId, .persona_id])
        content = try container.decode(String.self, forKey: .content)
        sourceType = try container.decodeFirst(String.self, forKeys: [.sourceType, .source_type])
        sourceUrl = RemoteMediaPolicy.normalizedSourceURLString(
            try container.decodeFirstIfPresent(String.self, forKeys: [.sourceUrl, .source_url])
        )
        topic = try container.decodeIfPresent(String.self, forKey: .topic)
        importanceScore = try container.decodeFirst(Double.self, forKeys: [.importanceScore, .importance_score])
        mediaUrls = RemoteMediaPolicy.normalizedMediaURLStrings(
            try container.decodeFirstIfPresent([String].self, forKeys: [.mediaUrls, .media_urls]) ?? []
        )
        videoUrl = RemoteMediaPolicy.normalizedAssetURLString(
            try container.decodeFirstIfPresent(String.self, forKeys: [.videoUrl, .video_url])
        )
        publishedAt = try container.decodeFirst(Date.self, forKeys: [.publishedAt, .published_at])
    }
}
