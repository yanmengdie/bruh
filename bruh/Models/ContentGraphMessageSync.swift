import Foundation
import SwiftData

extension ContentGraphStore {
    @MainActor
    static func syncIncomingMessage(_ message: PersonaMessage, in context: ModelContext) {
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

        let event = ContentGraphStoreSupport.fetchContentEvent(id: eventId, in: context) ?? {
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
        let delivery = ContentGraphStoreSupport.fetchContentDelivery(id: deliveryId, in: context) ?? {
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
    private static func syncAlbumDeliveryIfNeeded(
        for message: PersonaMessage,
        eventId: String,
        preview: String,
        in context: ModelContext
    ) {
        guard let imageUrl = ContentGraphStoreSupport.normalizedValue(message.imageUrl) else { return }

        let albumDeliveryId = "delivery:album:\(message.id)"
        let delivery = ContentGraphStoreSupport.fetchContentDelivery(id: albumDeliveryId, in: context) ?? {
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
}
