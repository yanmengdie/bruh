import Foundation
import SwiftData

extension ContentGraphStore {
    private struct FeedSyncCache {
        var sourceItemsById: [String: SourceItem]
        var eventsById: [String: ContentEvent]
        var deliveriesById: [String: ContentDelivery]
    }

    @MainActor
    static func syncFeedPosts(_ posts: [PersonaPost], in context: ModelContext) {
        guard !posts.isEmpty else { return }
        var cache = makeFeedSyncCache(for: posts, in: context)

        for post in posts {
            syncFeedPost(post, in: context, cache: &cache)
        }
    }

    @MainActor
    static func syncFeedPost(_ post: PersonaPost, in context: ModelContext) {
        var cache = makeFeedSyncCache(for: [post], in: context)
        syncFeedPost(post, in: context, cache: &cache)
    }

    @MainActor
    private static func syncFeedPost(
        _ post: PersonaPost,
        in context: ModelContext,
        cache: inout FeedSyncCache
    ) {
        let sourceItem = upsertSourceItem(for: post, in: context, cache: &cache)
        let eventId = "event:feed:\(post.id)"
        let preview = ContentGraphStoreSupport.previewText(text: post.content)
        let tags = [post.sourceType, post.topic, post.personaId].compactMap(ContentGraphStoreSupport.normalizedValue)

        let event = cache.eventsById[eventId] ?? {
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
            cache.eventsById[eventId] = item
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
        let delivery = cache.deliveriesById[deliveryId] ?? {
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
            cache.deliveriesById[deliveryId] = item
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
    private static func upsertSourceItem(
        for post: PersonaPost,
        in context: ModelContext,
        cache: inout FeedSyncCache
    ) -> SourceItem {
        let sourceItemId = "source:feed:\(post.id)"
        let sourceItem = cache.sourceItemsById[sourceItemId] ?? {
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
            cache.sourceItemsById[sourceItemId] = item
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

    @MainActor
    private static func makeFeedSyncCache(
        for posts: [PersonaPost],
        in context: ModelContext
    ) -> FeedSyncCache {
        let postIds = Array(Set(posts.map(\.id)))
        let sourceItemIds = postIds.map { "source:feed:\($0)" }
        let eventIds = postIds.map { "event:feed:\($0)" }
        let deliveryIds = postIds.map { "delivery:feed:\($0)" }

        return FeedSyncCache(
            sourceItemsById: fetchSourceItems(ids: sourceItemIds, in: context),
            eventsById: fetchContentEvents(ids: eventIds, in: context),
            deliveriesById: fetchContentDeliveries(ids: deliveryIds, in: context)
        )
    }

    @MainActor
    private static func fetchSourceItems(
        ids: [String],
        in context: ModelContext
    ) -> [String: SourceItem] {
        guard !ids.isEmpty else { return [:] }
        let descriptor = FetchDescriptor<SourceItem>(
            predicate: #Predicate<SourceItem> { ids.contains($0.id) }
        )
        let items = (try? context.fetch(descriptor)) ?? []
        return Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
    }

    @MainActor
    private static func fetchContentEvents(
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
    private static func fetchContentDeliveries(
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
