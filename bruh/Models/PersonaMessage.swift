import Foundation
import SwiftData

@Model
final class PersonaMessage {
    @Attribute(.unique) var id: String
    var threadId: String
    var personaId: String
    var text: String
    var isIncoming: Bool
    var createdAt: Date
    var deliveryState: String
    var sourcePostIds: [String]
    var isSeedMessage: Bool

    init(
        id: String,
        threadId: String,
        personaId: String,
        text: String,
        isIncoming: Bool,
        createdAt: Date = .now,
        deliveryState: String = "sent",
        sourcePostIds: [String] = [],
        isSeedMessage: Bool = false
    ) {
        self.id = id
        self.threadId = threadId
        self.personaId = personaId
        self.text = text
        self.isIncoming = isIncoming
        self.createdAt = createdAt
        self.deliveryState = deliveryState
        self.sourcePostIds = sourcePostIds
        self.isSeedMessage = isSeedMessage
    }
}
