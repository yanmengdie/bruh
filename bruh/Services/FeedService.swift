import Foundation
import SwiftData

/// Bridges remote PostDTO objects into local SwiftData PersonaPost rows.
@MainActor
final class FeedService {
    private let api: APIClient
    private let seedBaselineDate = Date(timeIntervalSince1970: 946684800) // 2000-01-01T00:00:00Z
    private let suspiciousDemoMarkers = ["example", "demo"]

    init(api: APIClient = APIClient()) {
        self.api = api
    }

    /// Pull new posts from the backend and insert into local store.
    /// Returns the number of new posts fetched.
    func refreshFeed(modelContext: ModelContext) async throws -> Int {
        try demoteSeedPostsIfNeeded(modelContext: modelContext)
        let since = try latestRemotePublishedAt(modelContext: modelContext)?.addingTimeInterval(-1)
        let dtos = try await api.fetchFeed(since: since, limit: 40)
        let fetchDate = Date()
        var newCount = 0

        for dto in dtos {
            var check = FetchDescriptor<PersonaPost>(
                predicate: #Predicate { $0.id == dto.id }
            )
            check.fetchLimit = 1
            if let existing = try modelContext.fetch(check).first {
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
                ContentGraphStore.syncFeedPost(existing, in: modelContext)
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
            ContentGraphStore.syncFeedPost(post, in: modelContext)
            newCount += 1
        }

        if modelContext.hasChanges {
            try modelContext.save()
        }
        return newCount
    }

    private func latestRemotePublishedAt(modelContext: ModelContext) throws -> Date? {
        var descriptor = FetchDescriptor<PersonaPost>(
            predicate: #Predicate { $0.isDelivered },
            sortBy: [SortDescriptor(\PersonaPost.publishedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first?.publishedAt
    }

    private func demoteSeedPostsIfNeeded(modelContext: ModelContext) throws {
        let posts = try modelContext.fetch(FetchDescriptor<PersonaPost>())
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
}
