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

@Model
final class PengyouMoment {
    @Attribute(.unique) var id: String
    var personaId: String
    var displayName: String
    var handle: String
    var avatarName: String
    var locationLabel: String
    var sourceType: String
    var exportedAt: Date
    var postId: String
    var content: String
    var sourceUrl: String?
    var mediaUrls: [String]
    var videoUrl: String?
    var publishedAt: Date
    var createdAt: Date
    var updatedAt: Date

    init(
        id: String,
        personaId: String,
        displayName: String,
        handle: String,
        avatarName: String,
        locationLabel: String,
        sourceType: String,
        exportedAt: Date = .now,
        postId: String,
        content: String,
        sourceUrl: String? = nil,
        mediaUrls: [String] = [],
        videoUrl: String? = nil,
        publishedAt: Date = .now,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.personaId = personaId
        self.displayName = displayName
        self.handle = handle
        self.avatarName = avatarName
        self.locationLabel = locationLabel
        self.sourceType = sourceType
        self.exportedAt = exportedAt
        self.postId = postId
        self.content = content
        self.sourceUrl = sourceUrl
        self.mediaUrls = mediaUrls
        self.videoUrl = videoUrl
        self.publishedAt = publishedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
