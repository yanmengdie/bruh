import Foundation
import SwiftData

@Model
final class PersonaPost {
    @Attribute(.unique) var id: String
    var personaId: String
    var contentEventId: String?
    var content: String
    var sourceType: String   // "x" | "news"
    var sourceUrl: String?
    var topic: String?
    var importanceScore: Double
    var mediaUrls: [String]
    var videoUrl: String?
    var publishedAt: Date
    var fetchedAt: Date
    var isDelivered: Bool

    init(
        id: String = UUID().uuidString,
        personaId: String,
        contentEventId: String? = nil,
        content: String,
        sourceType: String,
        sourceUrl: String? = nil,
        topic: String? = nil,
        importanceScore: Double = 0.5,
        mediaUrls: [String] = [],
        videoUrl: String? = nil,
        publishedAt: Date = .now,
        fetchedAt: Date = .now,
        isDelivered: Bool = false
    ) {
        self.id = id
        self.personaId = personaId
        self.contentEventId = contentEventId
        self.content = content
        self.sourceType = sourceType
        self.sourceUrl = sourceUrl
        self.topic = topic
        self.importanceScore = importanceScore
        self.mediaUrls = mediaUrls
        self.videoUrl = videoUrl
        self.publishedAt = publishedAt
        self.fetchedAt = fetchedAt
        self.isDelivered = isDelivered
    }
}
