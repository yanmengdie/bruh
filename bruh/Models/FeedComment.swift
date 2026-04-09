import Foundation
import SwiftData

@Model
final class FeedComment {
    @Attribute(.unique) var id: String
    var postId: String
    var authorId: String
    var authorDisplayName: String
    var content: String
    var reasonCode: String
    var generationMode: String
    var inReplyToCommentId: String?
    var isViewer: Bool
    var createdAt: Date
    var deliveryState: String

    init(
        id: String,
        postId: String,
        authorId: String,
        authorDisplayName: String,
        content: String,
        reasonCode: String,
        generationMode: String = "seed",
        inReplyToCommentId: String? = nil,
        isViewer: Bool = false,
        createdAt: Date = .now,
        deliveryState: String = "sent"
    ) {
        self.id = id
        self.postId = postId
        self.authorId = authorId
        self.authorDisplayName = authorDisplayName
        self.content = content
        self.reasonCode = reasonCode
        self.generationMode = generationMode
        self.inReplyToCommentId = inReplyToCommentId
        self.isViewer = isViewer
        self.createdAt = createdAt
        self.deliveryState = deliveryState
    }
}
