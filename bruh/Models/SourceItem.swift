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

enum ContentGraphStore {
    @MainActor
    static func syncFeedPost(_ post: PersonaPost, in context: ModelContext) {
        let sourceItem = upsertSourceItem(for: post, in: context)
        let eventId = "event:feed:\(post.id)"
        let preview = previewText(text: post.content)
        let tags = [post.sourceType, post.topic, post.personaId].compactMap { normalizedValue($0) }

        let event = fetchContentEvent(id: eventId, in: context) ?? {
            let item = ContentEvent(
                id: eventId,
                kind: ContentEventKind.socialPost.rawValue,
                sourceReferenceIds: [sourceItem.id, post.id],
                primaryPersonaId: post.personaId,
                title: preview,
                bodyText: post.content,
                summaryText: post.topic ?? "",
                canonicalUrl: post.sourceUrl,
                category: post.topic,
                interestTags: tags,
                publishedAt: post.publishedAt,
                fetchedAt: post.fetchedAt,
                updatedAt: .now
            )
            context.insert(item)
            return item
        }()

        event.kindValue = .socialPost
        event.sourceReferenceIds = deduplicated([sourceItem.id, post.id])
        event.primaryPersonaId = post.personaId
        event.title = preview
        event.bodyText = post.content
        event.summaryText = post.topic ?? ""
        event.canonicalUrl = normalizedValue(post.sourceUrl)
        event.category = normalizedValue(post.topic)
        event.interestTags = deduplicated(tags)
        event.publishedAt = post.publishedAt
        event.fetchedAt = post.fetchedAt
        event.updatedAt = .now
        post.contentEventId = eventId

        let deliveryId = "delivery:feed:\(post.id)"
        let delivery = fetchContentDelivery(id: deliveryId, in: context) ?? {
            let item = ContentDelivery(
                id: deliveryId,
                eventId: eventId,
                channel: ContentDeliveryChannel.feed.rawValue,
                personaId: post.personaId,
                legacyPostId: post.id,
                renderedText: post.content,
                previewText: preview,
                mediaUrls: post.mediaUrls,
                videoUrl: post.videoUrl,
                deliveredAt: post.fetchedAt,
                sortDate: post.publishedAt,
                isVisible: true
            )
            context.insert(item)
            return item
        }()

        delivery.eventId = eventId
        delivery.channelValue = .feed
        delivery.personaId = post.personaId
        delivery.threadId = nil
        delivery.legacyPostId = post.id
        delivery.legacyMessageId = nil
        delivery.renderedText = post.content
        delivery.previewText = preview
        delivery.imageUrl = nil
        delivery.mediaUrls = post.mediaUrls
        delivery.videoUrl = post.videoUrl
        delivery.deliveredAt = post.fetchedAt
        delivery.sortDate = post.publishedAt
        delivery.isVisible = true
        delivery.updatedAt = .now
    }

    @MainActor
    static func syncIncomingMessage(_ message: PersonaMessage, in context: ModelContext) {
        guard message.isIncoming else { return }

        let eventKind = resolvedEventKind(for: message)
        let eventId = message.contentEventId ?? "event:message:\(message.id)"
        let preview = previewText(text: message.text, imageUrl: message.imageUrl)
        let articleURL = firstURL(in: message.text)

        let event = fetchContentEvent(id: eventId, in: context) ?? {
            let item = ContentEvent(
                id: eventId,
                kind: eventKind.rawValue,
                sourceReferenceIds: message.sourcePostIds,
                primaryPersonaId: message.personaId,
                title: preview,
                bodyText: message.text,
                summaryText: "",
                canonicalUrl: articleURL,
                category: message.isSeedMessage ? "starter" : nil,
                interestTags: [],
                publishedAt: message.createdAt,
                fetchedAt: message.createdAt,
                updatedAt: .now
            )
            context.insert(item)
            return item
        }()

        event.kindValue = eventKind
        event.sourceReferenceIds = deduplicated(message.sourcePostIds)
        event.primaryPersonaId = message.personaId
        event.title = preview
        event.bodyText = message.text
        event.summaryText = ""
        event.canonicalUrl = articleURL
        event.category = message.isSeedMessage ? "starter" : nil
        event.interestTags = []
        event.publishedAt = message.createdAt
        event.fetchedAt = message.createdAt
        event.updatedAt = .now
        message.contentEventId = eventId

        let deliveryId = "delivery:message:\(message.id)"
        let delivery = fetchContentDelivery(id: deliveryId, in: context) ?? {
            let item = ContentDelivery(
                id: deliveryId,
                eventId: eventId,
                channel: ContentDeliveryChannel.message.rawValue,
                personaId: message.personaId,
                threadId: message.threadId,
                legacyMessageId: message.id,
                renderedText: message.text,
                previewText: preview,
                imageUrl: message.imageUrl,
                deliveredAt: message.createdAt,
                sortDate: message.createdAt,
                isVisible: true
            )
            context.insert(item)
            return item
        }()

        delivery.eventId = eventId
        delivery.channelValue = .message
        delivery.personaId = message.personaId
        delivery.threadId = message.threadId
        delivery.legacyPostId = nil
        delivery.legacyMessageId = message.id
        delivery.renderedText = message.text
        delivery.previewText = preview
        delivery.imageUrl = message.imageUrl
        delivery.mediaUrls = []
        delivery.videoUrl = nil
        delivery.deliveredAt = message.createdAt
        delivery.sortDate = message.createdAt
        delivery.isVisible = true
        delivery.updatedAt = .now

        syncAlbumDeliveryIfNeeded(for: message, eventId: eventId, preview: preview, in: context)
    }

    @MainActor
    static func backfill(in context: ModelContext) {
        let posts = (try? context.fetch(FetchDescriptor<PersonaPost>())) ?? []
        let messages = (try? context.fetch(FetchDescriptor<PersonaMessage>())) ?? []

        for post in posts {
            syncFeedPost(post, in: context)
        }

        for message in messages where message.isIncoming {
            syncIncomingMessage(message, in: context)
        }
    }

    @MainActor
    private static func upsertSourceItem(for post: PersonaPost, in context: ModelContext) -> SourceItem {
        let sourceItemId = "source:feed:\(post.id)"
        let sourceItem = fetchSourceItem(id: sourceItemId, in: context) ?? {
            let item = SourceItem(
                id: sourceItemId,
                sourceType: post.sourceType,
                sourceName: post.personaId,
                title: previewText(text: post.content),
                content: post.content,
                url: post.sourceUrl ?? "",
                tags: [post.topic, post.personaId].compactMap { normalizedValue($0) },
                publishedAt: post.publishedAt,
                fetchedAt: post.fetchedAt,
                isVerified: true,
                isProcessed: true
            )
            context.insert(item)
            return item
        }()

        sourceItem.sourceType = post.sourceType
        sourceItem.sourceName = post.personaId
        sourceItem.title = previewText(text: post.content)
        sourceItem.content = post.content
        sourceItem.url = post.sourceUrl ?? ""
        sourceItem.tags = deduplicated([post.topic, post.personaId].compactMap { normalizedValue($0) })
        sourceItem.publishedAt = post.publishedAt
        sourceItem.fetchedAt = post.fetchedAt
        sourceItem.isVerified = true
        sourceItem.isProcessed = true
        return sourceItem
    }

    @MainActor
    private static func syncAlbumDeliveryIfNeeded(
        for message: PersonaMessage,
        eventId: String,
        preview: String,
        in context: ModelContext
    ) {
        guard let imageUrl = normalizedValue(message.imageUrl) else { return }

        let albumDeliveryId = "delivery:album:\(message.id)"
        let delivery = fetchContentDelivery(id: albumDeliveryId, in: context) ?? {
            let item = ContentDelivery(
                id: albumDeliveryId,
                eventId: eventId,
                channel: ContentDeliveryChannel.album.rawValue,
                personaId: message.personaId,
                threadId: message.threadId,
                legacyMessageId: message.id,
                renderedText: message.text,
                previewText: preview,
                imageUrl: imageUrl,
                deliveredAt: message.createdAt,
                sortDate: message.createdAt,
                isVisible: true
            )
            context.insert(item)
            return item
        }()

        delivery.eventId = eventId
        delivery.channelValue = .album
        delivery.personaId = message.personaId
        delivery.threadId = message.threadId
        delivery.legacyPostId = nil
        delivery.legacyMessageId = message.id
        delivery.renderedText = message.text
        delivery.previewText = preview
        delivery.imageUrl = imageUrl
        delivery.mediaUrls = []
        delivery.videoUrl = nil
        delivery.deliveredAt = message.createdAt
        delivery.sortDate = message.createdAt
        delivery.isVisible = true
        delivery.updatedAt = .now
    }

    @MainActor
    private static func fetchSourceItem(id: String, in context: ModelContext) -> SourceItem? {
        var descriptor = FetchDescriptor<SourceItem>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    @MainActor
    private static func fetchContentEvent(id: String, in context: ModelContext) -> ContentEvent? {
        var descriptor = FetchDescriptor<ContentEvent>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    @MainActor
    private static func fetchContentDelivery(id: String, in context: ModelContext) -> ContentDelivery? {
        var descriptor = FetchDescriptor<ContentDelivery>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    private static func resolvedEventKind(for message: PersonaMessage) -> ContentEventKind {
        if normalizedValue(message.imageUrl) != nil {
            return .generatedImage
        }
        if message.isSeedMessage || !message.sourcePostIds.isEmpty {
            return .messageStarter
        }
        return .messageReply
    }

    private static func previewText(text: String, imageUrl: String? = nil) -> String {
        let trimmed = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)

        let base = trimmed.isEmpty ? (imageUrl == nil ? "Untitled" : "[图片]") : String(trimmed.prefix(80))
        return base
    }

    private static func firstURL(in text: String) -> String? {
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return detector?
            .matches(in: text, options: [], range: range)
            .compactMap { $0.url?.absoluteString }
            .first
    }

    private static func normalizedValue(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    private static func deduplicated(_ values: [String]) -> [String] {
        Array(NSOrderedSet(array: values)) as? [String] ?? values
    }
}
