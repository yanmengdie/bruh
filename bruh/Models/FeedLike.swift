import Foundation
import SwiftData

@Model
final class FeedLike {
    @Attribute(.unique) var id: String
    var postId: String
    var authorId: String
    var authorDisplayName: String
    var reasonCode: String
    var generationMode: String
    var createdAt: Date
    var isViewer: Bool

    init(
        id: String,
        postId: String,
        authorId: String,
        authorDisplayName: String,
        reasonCode: String,
        generationMode: String = "seed",
        createdAt: Date = .now,
        isViewer: Bool = false
    ) {
        self.id = id
        self.postId = postId
        self.authorId = authorId
        self.authorDisplayName = authorDisplayName
        self.reasonCode = reasonCode
        self.generationMode = generationMode
        self.createdAt = createdAt
        self.isViewer = isViewer
    }
}

@Model
final class FeedInteractionSeedState {
    @Attribute(.unique) var postId: String
    var generationVersion: Int
    var strategy: String
    var seededAt: Date
    var updatedAt: Date

    init(
        postId: String,
        generationVersion: Int,
        strategy: String,
        seededAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.postId = postId
        self.generationVersion = generationVersion
        self.strategy = strategy
        self.seededAt = seededAt
        self.updatedAt = updatedAt
    }
}
