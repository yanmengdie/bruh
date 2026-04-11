import Foundation
import SwiftData

@MainActor
struct MessageThreadStore {
    func acceptedPersonaIds(modelContext: ModelContext) throws -> [String] {
        let contacts = try modelContext.fetch(FetchDescriptor<Contact>())
        let ids = contacts
            .filter { $0.relationshipStatusValue == .accepted }
            .compactMap(\.linkedPersonaId)
        return Array(NSOrderedSet(array: ids)) as? [String] ?? ids
    }

    func ensureThread(for personaId: String, modelContext: ModelContext) throws -> MessageThread {
        var descriptor = FetchDescriptor<MessageThread>(
            predicate: #Predicate { $0.id == personaId }
        )
        descriptor.fetchLimit = 1

        if let existing = try modelContext.fetch(descriptor).first {
            return existing
        }

        let thread = MessageThread(
            id: personaId,
            personaId: personaId,
            lastMessagePreview: "",
            lastMessageAt: .distantPast,
            unreadCount: 0
        )
        modelContext.insert(thread)
        return thread
    }

    func recentConversation(
        for threadId: String,
        modelContext: ModelContext,
        limit: Int = 6
    ) throws -> [MessageTurnDTO] {
        var descriptor = FetchDescriptor<PersonaMessage>(
            predicate: #Predicate { $0.threadId == threadId },
            sortBy: [SortDescriptor(\PersonaMessage.createdAt, order: .reverse)]
        )
        descriptor.fetchLimit = limit

        return try modelContext.fetch(descriptor)
            .reversed()
            .map { message in
                MessageTurnDTO(
                    role: message.isIncoming ? "assistant" : "user",
                    content: message.text
                )
            }
    }

    func latestIncomingMessageDate(for personaId: String, modelContext: ModelContext) throws -> Date? {
        let threadId = personaId
        var descriptor = FetchDescriptor<PersonaMessage>(
            predicate: #Predicate { $0.threadId == threadId && $0.isIncoming },
            sortBy: [SortDescriptor(\PersonaMessage.createdAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first?.createdAt
    }

    func shouldForceVoiceReply(for threadId: String, modelContext: ModelContext) throws -> Bool {
        var descriptor = FetchDescriptor<PersonaMessage>(
            predicate: #Predicate { $0.threadId == threadId && $0.isIncoming },
            sortBy: [SortDescriptor(\PersonaMessage.createdAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1

        guard let latestIncoming = try modelContext.fetch(descriptor).first else {
            return true
        }

        return !MessageServiceSupport.hasPlayableAudio(latestIncoming)
    }

    func starterMessage(for personaId: String, modelContext: ModelContext) throws -> PersonaMessage? {
        let starterMessages = try starterMessages(for: personaId, modelContext: modelContext)
        if let canonical = starterMessages.first(where: { $0.id == MessageServiceSupport.starterMessageId(for: personaId) }) {
            return canonical
        }
        return starterMessages.first
    }

    func starterMessages(for personaId: String, modelContext: ModelContext) throws -> [PersonaMessage] {
        let descriptor = FetchDescriptor<PersonaMessage>(
            predicate: #Predicate { $0.threadId == personaId && $0.isSeedMessage },
            sortBy: [SortDescriptor(\PersonaMessage.createdAt, order: .forward)]
        )
        return try modelContext.fetch(descriptor)
    }

    func hasConversationHistoryBeyondStarter(for personaId: String, modelContext: ModelContext) throws -> Bool {
        let descriptor = FetchDescriptor<PersonaMessage>(
            predicate: #Predicate { $0.threadId == personaId && $0.isSeedMessage == false }
        )
        return try modelContext.fetch(descriptor).contains { message in
            message.id != MessageServiceSupport.trumpWebPreviewDemoMessageId
        }
    }

    func fetchContentDelivery(id: String, modelContext: ModelContext) throws -> ContentDelivery? {
        var descriptor = FetchDescriptor<ContentDelivery>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    func fetchContentEvent(id: String, modelContext: ModelContext) throws -> ContentEvent? {
        var descriptor = FetchDescriptor<ContentEvent>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    func nextUnreadCount(afterReceivingMessageAt date: Date, on thread: MessageThread) -> Int {
        guard date > (thread.lastReadAt ?? .distantPast) else {
            return max(0, thread.unreadCount)
        }
        return max(0, thread.unreadCount) + 1
    }

    func updateThread(_ thread: MessageThread, preview: String, at date: Date, unreadCount: Int) {
        thread.lastMessagePreview = preview
        thread.lastMessageAt = date
        thread.updatedAt = .now
        thread.unreadCount = unreadCount
    }
}
