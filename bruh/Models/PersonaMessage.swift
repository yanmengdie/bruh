import Foundation
import SwiftData

@Model
final class PersonaMessage {
    @Attribute(.unique) var id: String
    var threadId: String
    var personaId: String
    var contentEventId: String?
    var text: String
    var imageUrl: String?
    var isIncoming: Bool
    var createdAt: Date
    var deliveryState: String
    var sourcePostIds: [String] // upstream ids from backend, can be source post ids or news event ids
    var isSeedMessage: Bool

    init(
        id: String,
        threadId: String,
        personaId: String,
        contentEventId: String? = nil,
        text: String,
        imageUrl: String? = nil,
        isIncoming: Bool,
        createdAt: Date = .now,
        deliveryState: String = "sent",
        sourcePostIds: [String] = [],
        isSeedMessage: Bool = false
    ) {
        self.id = id
        self.threadId = threadId
        self.personaId = personaId
        self.contentEventId = contentEventId
        self.text = text
        self.imageUrl = imageUrl
        self.isIncoming = isIncoming
        self.createdAt = createdAt
        self.deliveryState = deliveryState
        self.sourcePostIds = sourcePostIds
        self.isSeedMessage = isSeedMessage
    }
}
