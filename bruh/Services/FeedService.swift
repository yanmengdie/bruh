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

final class PengyouMomentRemoteSyncService {
    private let api: APIClient
    private let remoteFeedWindow: Int
    private static let remoteIdPrefix = "remote:"

    init(
        api: APIClient = APIClient(),
        remoteFeedWindow: Int = 80
    ) {
        self.api = api
        self.remoteFeedWindow = remoteFeedWindow
    }

    @MainActor
    func refreshMoments(modelContext: ModelContext) async throws -> Int {
        let dtos = try await api.fetchFeed(limit: remoteFeedWindow)
        let fetchedAt = Date()
        let moments = try modelContext.fetch(FetchDescriptor<PengyouMoment>())
        var momentsById = Dictionary(uniqueKeysWithValues: moments.map { ($0.id, $0) })
        let activeRemoteIds = Set(dtos.map { Self.momentId(forFeedId: $0.id) })
        var insertedCount = 0

        for dto in dtos {
            let momentId = Self.momentId(forFeedId: dto.id)

            if let existing = momentsById[momentId] {
                Self.apply(dto, to: existing, fetchedAt: fetchedAt)
                continue
            }

            let moment = Self.makeMoment(from: dto, fetchedAt: fetchedAt)
            modelContext.insert(moment)
            momentsById[momentId] = moment
            insertedCount += 1
        }

        if !activeRemoteIds.isEmpty {
            for moment in moments where Self.isRemoteMoment(moment) && !activeRemoteIds.contains(moment.id) {
                modelContext.delete(moment)
            }
        }

        if modelContext.hasChanges {
            try modelContext.save()
        }

        return insertedCount
    }

    private static func isRemoteMoment(_ moment: PengyouMoment) -> Bool {
        moment.id.hasPrefix(remoteIdPrefix)
    }

    private static func momentId(forFeedId feedId: String) -> String {
        "\(remoteIdPrefix)\(feedId)"
    }

    @MainActor
    private static func makeMoment(from dto: PostDTO, fetchedAt: Date) -> PengyouMoment {
        let metadata = metadata(for: dto)
        return PengyouMoment(
            id: momentId(forFeedId: dto.id),
            personaId: dto.personaId,
            displayName: metadata.displayName,
            handle: metadata.handle,
            avatarName: metadata.avatarName,
            locationLabel: metadata.locationLabel,
            sourceType: dto.sourceType,
            exportedAt: fetchedAt,
            postId: dto.id,
            content: dto.content,
            sourceUrl: dto.sourceUrl,
            mediaUrls: dto.mediaUrls,
            videoUrl: dto.videoUrl,
            publishedAt: dto.publishedAt,
            createdAt: fetchedAt,
            updatedAt: fetchedAt
        )
    }

    @MainActor
    private static func apply(_ dto: PostDTO, to moment: PengyouMoment, fetchedAt: Date) {
        let metadata = metadata(for: dto)
        moment.personaId = dto.personaId
        moment.displayName = metadata.displayName
        moment.handle = metadata.handle
        moment.avatarName = metadata.avatarName
        moment.locationLabel = metadata.locationLabel
        moment.sourceType = dto.sourceType
        moment.exportedAt = fetchedAt
        moment.postId = dto.id
        moment.content = dto.content
        moment.sourceUrl = dto.sourceUrl
        moment.mediaUrls = dto.mediaUrls
        moment.videoUrl = dto.videoUrl
        moment.publishedAt = dto.publishedAt
        moment.updatedAt = fetchedAt
    }

    @MainActor
    private static func metadata(for dto: PostDTO) -> (
        displayName: String,
        handle: String,
        avatarName: String,
        locationLabel: String
    ) {
        guard let entry = PersonaCatalog.entry(for: dto.personaId) else {
            return (
                displayName: dto.personaId,
                handle: "@\(dto.personaId)",
                avatarName: "",
                locationLabel: fallbackLocationLabel(for: dto.sourceType)
            )
        }

        let platformHandle = entry.platformAccounts.first {
            $0.isActive && $0.platform.caseInsensitiveCompare(dto.sourceType) == .orderedSame
        }?.handle ?? entry.handle

        return (
            displayName: entry.displayName,
            handle: normalizedHandle(platformHandle),
            avatarName: entry.avatarName,
            locationLabel: entry.locationLabel.isEmpty ? fallbackLocationLabel(for: dto.sourceType) : entry.locationLabel
        )
    }

    private static func normalizedHandle(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "@unknown" }
        return trimmed.hasPrefix("@") ? trimmed : "@\(trimmed)"
    }

    private static func fallbackLocationLabel(for sourceType: String) -> String {
        switch sourceType.lowercased() {
        case "weibo":
            return "中国"
        case "x":
            return "X"
        default:
            return "动态"
        }
    }
}
