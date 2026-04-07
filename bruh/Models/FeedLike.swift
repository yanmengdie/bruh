import Foundation
import SwiftData

@Model
final class FeedLike {
    @Attribute(.unique) var id: String
    var postId: String
    var authorId: String
    var authorDisplayName: String
    var reasonCode: String
    var createdAt: Date
    var isViewer: Bool

    init(
        id: String,
        postId: String,
        authorId: String,
        authorDisplayName: String,
        reasonCode: String,
        createdAt: Date = .now,
        isViewer: Bool = false
    ) {
        self.id = id
        self.postId = postId
        self.authorId = authorId
        self.authorDisplayName = authorDisplayName
        self.reasonCode = reasonCode
        self.createdAt = createdAt
        self.isViewer = isViewer
    }
}
