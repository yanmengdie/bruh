import Foundation
import SwiftData

extension ContentGraphStore {
    private struct MessageSyncCache {
        var eventsById: [String: ContentEvent]
        var deliveriesById: [String: ContentDelivery]
    }

    @MainActor
    static func syncIncomingMessages(_ messages: [PersonaMessage], in context: ModelContext) {
        let incomingMessages = messages.filter(\.isIncoming)
        guard !incomingMessages.isEmpty else { return }
        var cache = makeMessageSyncCache(for: incomingMessages, in: context)

        for message in incomingMessages {
            syncIncomingMessage(message, in: context, cache: &cache)
        }
    }

    @MainActor
    static func syncIncomingMessage(_ message: PersonaMessage, in context: ModelContext) {
        var cache = makeMessageSyncCache(for: [message], in: context)
        syncIncomingMessage(message, in: context, cache: &cache)
    }

    @MainActor
    private static func syncIncomingMessage(
        _ message: PersonaMessage,
        in context: ModelContext,
        cache: inout MessageSyncCache
    ) {
        guard message.isIncoming else { return }

        let eventKind = ContentGraphStoreSupport.resolvedEventKind(for: message)
        let eventId = message.contentEventId ?? "event:message:\(message.id)"
        let preview = ContentGraphStoreSupport.previewText(
            text: message.text,
            imageUrl: message.imageUrl,
            audioUrl: message.audioUrl,
            audioOnly: message.audioOnly
        )
        let articleURL = ContentGraphStoreSupport.firstURL(in: message.text)
            ?? ContentGraphStoreSupport.normalizedValue(message.sourceUrl)

        let event = cache.eventsById[eventId] ?? {
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
            cache.eventsById[eventId] = item
            return item
        }()

        event.kindValue = eventKind
        event.sourceReferenceIds = ContentGraphStoreSupport.deduplicated(message.sourcePostIds)
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
        let delivery = cache.deliveriesById[deliveryId] ?? {
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
            cache.deliveriesById[deliveryId] = item
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

        syncAlbumDeliveryIfNeeded(for: message, eventId: eventId, preview: preview, in: context, cache: &cache)
    }

    @MainActor
    private static func syncAlbumDeliveryIfNeeded(
        for message: PersonaMessage,
        eventId: String,
        preview: String,
        in context: ModelContext,
        cache: inout MessageSyncCache
    ) {
        guard let imageUrl = ContentGraphStoreSupport.normalizedValue(message.imageUrl) else { return }

        let albumDeliveryId = "delivery:album:\(message.id)"
        let delivery = cache.deliveriesById[albumDeliveryId] ?? {
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
            cache.deliveriesById[albumDeliveryId] = item
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
    private static func makeMessageSyncCache(
        for messages: [PersonaMessage],
        in context: ModelContext
    ) -> MessageSyncCache {
        let eventIds = messages.map { $0.contentEventId ?? "event:message:\($0.id)" }
        let messageDeliveryIds = messages.map { "delivery:message:\($0.id)" }
        let albumDeliveryIds = messages
            .filter { ContentGraphStoreSupport.normalizedValue($0.imageUrl) != nil }
            .map { "delivery:album:\($0.id)" }

        return MessageSyncCache(
            eventsById: fetchMessageContentEvents(ids: Array(Set(eventIds)), in: context),
            deliveriesById: fetchMessageContentDeliveries(
                ids: Array(Set(messageDeliveryIds + albumDeliveryIds)),
                in: context
            )
        )
    }

    @MainActor
    private static func fetchMessageContentEvents(
        ids: [String],
        in context: ModelContext
    ) -> [String: ContentEvent] {
        guard !ids.isEmpty else { return [:] }
        let descriptor = FetchDescriptor<ContentEvent>(
            predicate: #Predicate<ContentEvent> { ids.contains($0.id) }
        )
        let events = (try? context.fetch(descriptor)) ?? []
        return Dictionary(uniqueKeysWithValues: events.map { ($0.id, $0) })
    }

    @MainActor
    private static func fetchMessageContentDeliveries(
        ids: [String],
        in context: ModelContext
    ) -> [String: ContentDelivery] {
        guard !ids.isEmpty else { return [:] }
        let descriptor = FetchDescriptor<ContentDelivery>(
            predicate: #Predicate<ContentDelivery> { ids.contains($0.id) }
        )
        let deliveries = (try? context.fetch(descriptor)) ?? []
        return Dictionary(uniqueKeysWithValues: deliveries.map { ($0.id, $0) })
    }
}
