import Foundation
import SwiftData

extension ContentGraphStore {
    @MainActor
    static func syncFeedPost(_ post: PersonaPost, in context: ModelContext) {
        let sourceItem = upsertSourceItem(for: post, in: context)
        let eventId = "event:feed:\(post.id)"
        let preview = ContentGraphStoreSupport.previewText(text: post.content)
        let tags = [post.sourceType, post.topic, post.personaId].compactMap(ContentGraphStoreSupport.normalizedValue)

        let event = ContentGraphStoreSupport.fetchContentEvent(id: eventId, in: context) ?? {
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
        event.sourceReferenceIds = ContentGraphStoreSupport.deduplicated([sourceItem.id, post.id])
        event.primaryPersonaId = post.personaId
        event.title = preview
        event.bodyText = post.content
        event.summaryText = post.topic ?? ""
        event.canonicalUrl = ContentGraphStoreSupport.normalizedValue(post.sourceUrl)
        event.category = ContentGraphStoreSupport.normalizedValue(post.topic)
        event.interestTags = ContentGraphStoreSupport.deduplicated(tags)
        event.publishedAt = post.publishedAt
        event.fetchedAt = post.fetchedAt
        event.updatedAt = .now
        post.contentEventId = eventId

        let deliveryId = "delivery:feed:\(post.id)"
        let delivery = ContentGraphStoreSupport.fetchContentDelivery(id: deliveryId, in: context) ?? {
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
    private static func upsertSourceItem(for post: PersonaPost, in context: ModelContext) -> SourceItem {
        let sourceItemId = "source:feed:\(post.id)"
        let sourceItem = ContentGraphStoreSupport.fetchSourceItem(id: sourceItemId, in: context) ?? {
            let item = SourceItem(
                id: sourceItemId,
                sourceType: post.sourceType,
                sourceName: post.personaId,
                title: ContentGraphStoreSupport.previewText(text: post.content),
                content: post.content,
                url: post.sourceUrl ?? "",
                tags: [post.topic, post.personaId].compactMap(ContentGraphStoreSupport.normalizedValue),
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
        sourceItem.title = ContentGraphStoreSupport.previewText(text: post.content)
        sourceItem.content = post.content
        sourceItem.url = post.sourceUrl ?? ""
        sourceItem.tags = ContentGraphStoreSupport.deduplicated(
            [post.topic, post.personaId].compactMap(ContentGraphStoreSupport.normalizedValue)
        )
        sourceItem.publishedAt = post.publishedAt
        sourceItem.fetchedAt = post.fetchedAt
        sourceItem.isVerified = true
        sourceItem.isProcessed = true
        return sourceItem
    }
}
