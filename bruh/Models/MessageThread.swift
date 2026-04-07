import Foundation
import SwiftData

@Model
final class MessageThread {
    @Attribute(.unique) var id: String
    var personaId: String
    var lastMessagePreview: String
    var lastMessageAt: Date
    var unreadCount: Int
    var createdAt: Date
    var updatedAt: Date

    init(
        id: String,
        personaId: String,
        lastMessagePreview: String,
        lastMessageAt: Date,
        unreadCount: Int = 0,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.personaId = personaId
        self.lastMessagePreview = lastMessagePreview
        self.lastMessageAt = lastMessageAt
        self.unreadCount = unreadCount
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
