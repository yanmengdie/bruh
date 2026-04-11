import Foundation
import SwiftData

enum ContentEventKind: String, CaseIterable {
    case socialPost
    case messageStarter
    case messageReply
    case generatedImage
}

enum ContentDeliveryChannel: String, CaseIterable {
    case feed
    case message
    case album
}

@Model
final class SourceItem {
    @Attribute(.unique) var id: String
    var sourceType: String       // "x" | "news_rss" | "news_api"
    var sourceName: String
    var title: String
    var content: String
    var url: String
    var tags: [String]
    var publishedAt: Date
    var fetchedAt: Date
    var isVerified: Bool
    var isProcessed: Bool

    init(
        id: String = UUID().uuidString,
        sourceType: String,
        sourceName: String,
        title: String,
        content: String,
        url: String,
        tags: [String] = [],
        publishedAt: Date = .now,
        fetchedAt: Date = .now,
        isVerified: Bool = false,
        isProcessed: Bool = false
    ) {
        self.id = id
        self.sourceType = sourceType
        self.sourceName = sourceName
        self.title = title
        self.content = content
        self.url = url
        self.tags = tags
        self.publishedAt = publishedAt
        self.fetchedAt = fetchedAt
        self.isVerified = isVerified
        self.isProcessed = isProcessed
    }
}

@Model
final class ContentEvent {
    @Attribute(.unique) var id: String
    var kind: String
    var sourceReferenceIds: [String]
    var primaryPersonaId: String?
    var title: String
    var bodyText: String
    var summaryText: String
    var canonicalUrl: String?
    var category: String?
    var interestTags: [String]
    var publishedAt: Date
    var fetchedAt: Date
    var updatedAt: Date

    init(
        id: String,
        kind: String,
        sourceReferenceIds: [String] = [],
        primaryPersonaId: String? = nil,
        title: String,
        bodyText: String,
        summaryText: String = "",
        canonicalUrl: String? = nil,
        category: String? = nil,
        interestTags: [String] = [],
        publishedAt: Date = .now,
        fetchedAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.kind = kind
        self.sourceReferenceIds = sourceReferenceIds
        self.primaryPersonaId = primaryPersonaId
        self.title = title
        self.bodyText = bodyText
        self.summaryText = summaryText
        self.canonicalUrl = canonicalUrl
        self.category = category
        self.interestTags = interestTags
        self.publishedAt = publishedAt
        self.fetchedAt = fetchedAt
        self.updatedAt = updatedAt
    }
}

extension ContentEvent {
    var kindValue: ContentEventKind {
        get { ContentEventKind(rawValue: kind) ?? .messageReply }
        set { kind = newValue.rawValue }
    }
}

@Model
final class ContentDelivery {
    @Attribute(.unique) var id: String
    var eventId: String
    var channel: String
    var personaId: String?
    var threadId: String?
    var legacyPostId: String?
    var legacyMessageId: String?
    var renderedText: String
    var previewText: String
    var imageUrl: String?
    var mediaUrls: [String]
    var videoUrl: String?
    var deliveredAt: Date
    var sortDate: Date
    var isVisible: Bool
    var createdAt: Date
    var updatedAt: Date

    init(
        id: String,
        eventId: String,
        channel: String,
        personaId: String? = nil,
        threadId: String? = nil,
        legacyPostId: String? = nil,
        legacyMessageId: String? = nil,
        renderedText: String,
        previewText: String,
        imageUrl: String? = nil,
        mediaUrls: [String] = [],
        videoUrl: String? = nil,
        deliveredAt: Date = .now,
        sortDate: Date = .now,
        isVisible: Bool = true,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.eventId = eventId
        self.channel = channel
        self.personaId = personaId
        self.threadId = threadId
        self.legacyPostId = legacyPostId
        self.legacyMessageId = legacyMessageId
        self.renderedText = renderedText
        self.previewText = previewText
        self.imageUrl = imageUrl
        self.mediaUrls = mediaUrls
        self.videoUrl = videoUrl
        self.deliveredAt = deliveredAt
        self.sortDate = sortDate
        self.isVisible = isVisible
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

extension ContentDelivery {
    var channelValue: ContentDeliveryChannel {
        get { ContentDeliveryChannel(rawValue: channel) ?? .message }
        set { channel = newValue.rawValue }
    }
}
