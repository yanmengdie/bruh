import Foundation
import SwiftData

/// Bridges remote PostDTO objects into local SwiftData PersonaPost rows.
@MainActor
final class FeedService {
    private let api: APIClient
    private let remoteFeedWindow = 50
    private let seedBaselineDate = Date(timeIntervalSince1970: 946684800) // 2000-01-01T00:00:00Z
    private let suspiciousDemoMarkers = ["example", "demo"]

    init(api: APIClient = APIClient()) {
        self.api = api
    }

    /// Pull new posts from the backend and insert into local store.
    /// Returns the number of new posts fetched.
    func refreshFeed(modelContext: ModelContext) async throws -> Int {
        var posts = try modelContext.fetch(FetchDescriptor<PersonaPost>())
        try demoteSeedPostsIfNeeded(posts: posts, modelContext: modelContext)

        var postsById = Dictionary(uniqueKeysWithValues: posts.map { ($0.id, $0) })
        let dtos = try await api.fetchFeed(limit: remoteFeedWindow)
        let fetchDate = Date()
        var newCount = 0
        var syncedPosts: [PersonaPost] = []
        let activeIds = Set(dtos.map(\.id))

        for dto in dtos {
            if let existing = postsById[dto.id] {
                existing.personaId = dto.personaId
                existing.content = dto.content
                existing.sourceType = dto.sourceType
                existing.sourceUrl = dto.sourceUrl
                existing.topic = dto.topic
                existing.importanceScore = dto.importanceScore
                existing.mediaUrls = dto.mediaUrls
                existing.videoUrl = dto.videoUrl
                existing.publishedAt = dto.publishedAt
                existing.fetchedAt = fetchDate
                existing.isDelivered = true
                syncedPosts.append(existing)
                continue
            }

            let post = PersonaPost(
                id: dto.id,
                personaId: dto.personaId,
                content: dto.content,
                sourceType: dto.sourceType,
                sourceUrl: dto.sourceUrl,
                topic: dto.topic,
                importanceScore: dto.importanceScore,
                mediaUrls: dto.mediaUrls,
                videoUrl: dto.videoUrl,
                publishedAt: dto.publishedAt,
                fetchedAt: fetchDate,
                isDelivered: true
            )
            modelContext.insert(post)
            posts.append(post)
            postsById[post.id] = post
            syncedPosts.append(post)
            newCount += 1
        }

        ContentGraphStore.syncFeedPosts(syncedPosts, in: modelContext)

        try reconcileVisibleFeedWindow(
            activeIds: activeIds,
            posts: posts,
            modelContext: modelContext,
        )

        if modelContext.hasChanges {
            try modelContext.save()
        }
        return newCount
    }

    private func demoteSeedPostsIfNeeded(
        posts: [PersonaPost],
        modelContext: ModelContext
    ) throws {
        var didChange = false

        for post in posts where isLikelySeedPost(post) && post.publishedAt > seedBaselineDate {
            post.publishedAt = seedBaselineDate
            if post.fetchedAt > seedBaselineDate {
                post.fetchedAt = seedBaselineDate
            }
            ContentGraphStore.syncFeedPost(post, in: modelContext)
            didChange = true
        }

        if didChange && modelContext.hasChanges {
            try modelContext.save()
        }
    }

    private func isLikelySeedPost(_ post: PersonaPost) -> Bool {
        if post.id.lowercased().contains("demo") {
            return true
        }

        guard let sourceUrl = post.sourceUrl?.lowercased() else {
            return false
        }

        return suspiciousDemoMarkers.contains(where: sourceUrl.contains)
    }

    private func reconcileVisibleFeedWindow(
        activeIds: Set<String>,
        posts: [PersonaPost],
        modelContext: ModelContext
    ) throws {
        let deliveryIds = posts
            .lazy
            .filter { !self.isLikelySeedPost($0) }
            .map { "delivery:feed:\($0.id)" }
        let deliveriesById = try fetchFeedDeliveries(
            ids: Array(deliveryIds),
            modelContext: modelContext
        )

        for post in posts where !isLikelySeedPost(post) {
            let isActive = activeIds.contains(post.id)
            if post.isDelivered != isActive {
                post.isDelivered = isActive
            }

            guard let delivery = deliveriesById["delivery:feed:\(post.id)"] else {
                continue
            }

            if delivery.isVisible != isActive {
                delivery.isVisible = isActive
                delivery.updatedAt = .now
            }
        }
    }

    private func fetchFeedDeliveries(
        ids: [String],
        modelContext: ModelContext
    ) throws -> [String: ContentDelivery] {
        guard !ids.isEmpty else { return [:] }
        let descriptor = FetchDescriptor<ContentDelivery>(
            predicate: #Predicate<ContentDelivery> { ids.contains($0.id) }
        )
        let deliveries = try modelContext.fetch(descriptor)
        return Dictionary(uniqueKeysWithValues: deliveries.map { ($0.id, $0) })
    }
}
