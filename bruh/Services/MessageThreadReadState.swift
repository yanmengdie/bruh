import Foundation

enum MessageThreadReadState {
    static func markRead(thread: MessageThread, at date: Date?) {
        if let date {
            let existing = thread.lastReadAt ?? .distantPast
            if date > existing {
                thread.lastReadAt = date
            }
        }
        thread.unreadCount = 0
        thread.updatedAt = .now
    }

    static func unreadCount(for thread: MessageThread, deliveries: [ContentDelivery]) -> Int {
        let threadDeliveries = deliveries.filter { delivery in
            if let threadId = delivery.threadId, threadId == thread.id {
                return true
            }
            return delivery.personaId == thread.personaId
        }
        guard !threadDeliveries.isEmpty else { return max(0, thread.unreadCount) }

        let cutoff = thread.lastReadAt ?? .distantPast
        return threadDeliveries.reduce(0) { count, delivery in
            count + (delivery.sortDate > cutoff ? 1 : 0)
        }
    }
}
