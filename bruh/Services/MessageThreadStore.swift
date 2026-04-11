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

    func ensureThreads(for personaIds: [String], modelContext: ModelContext) throws -> [String: MessageThread] {
        let dedupedPersonaIds = Array(NSOrderedSet(array: personaIds)) as? [String] ?? personaIds
        guard !dedupedPersonaIds.isEmpty else { return [:] }

        let descriptor = FetchDescriptor<MessageThread>(
            predicate: #Predicate<MessageThread> { dedupedPersonaIds.contains($0.id) }
        )
        let existingThreads = try modelContext.fetch(descriptor)
        var threadsById = Dictionary(uniqueKeysWithValues: existingThreads.map { ($0.id, $0) })

        for personaId in dedupedPersonaIds where threadsById[personaId] == nil {
            let thread = MessageThread(
                id: personaId,
                personaId: personaId,
                lastMessagePreview: "",
                lastMessageAt: .distantPast,
                unreadCount: 0
            )
            modelContext.insert(thread)
            threadsById[personaId] = thread
        }

        return threadsById
    }

    func ensureThread(for personaId: String, modelContext: ModelContext) throws -> MessageThread {
        try ensureThreads(for: [personaId], modelContext: modelContext)[personaId]
            ?? {
                let thread = MessageThread(
                    id: personaId,
                    personaId: personaId,
                    lastMessagePreview: "",
                    lastMessageAt: .distantPast,
                    unreadCount: 0
                )
                modelContext.insert(thread)
                return thread
            }()
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

    func starterMessagesByPersonaId(
        for personaIds: [String],
        modelContext: ModelContext
    ) throws -> [String: [PersonaMessage]] {
        let dedupedPersonaIds = Array(NSOrderedSet(array: personaIds)) as? [String] ?? personaIds
        guard !dedupedPersonaIds.isEmpty else { return [:] }

        let descriptor = FetchDescriptor<PersonaMessage>(
            predicate: #Predicate<PersonaMessage> { dedupedPersonaIds.contains($0.threadId) && $0.isSeedMessage },
            sortBy: [SortDescriptor(\PersonaMessage.createdAt, order: .forward)]
        )
        let messages = try modelContext.fetch(descriptor)
        return Dictionary(grouping: messages, by: \.threadId)
    }

    func canonicalStarterMessagesByPersonaId(
        for personaIds: [String],
        modelContext: ModelContext
    ) throws -> [String: PersonaMessage] {
        let starterMessagesByPersona = try starterMessagesByPersonaId(for: personaIds, modelContext: modelContext)
        var canonicalByPersona: [String: PersonaMessage] = [:]

        for personaId in personaIds {
            guard let starterMessages = starterMessagesByPersona[personaId], !starterMessages.isEmpty else {
                continue
            }
            if let canonical = starterMessages.first(where: { $0.id == MessageServiceSupport.starterMessageId(for: personaId) }) {
                canonicalByPersona[personaId] = canonical
            } else {
                canonicalByPersona[personaId] = starterMessages.first
            }
        }

        return canonicalByPersona
    }

    func hasConversationHistoryBeyondStarter(for personaId: String, modelContext: ModelContext) throws -> Bool {
        let descriptor = FetchDescriptor<PersonaMessage>(
            predicate: #Predicate { $0.threadId == personaId && $0.isSeedMessage == false }
        )
        return try modelContext.fetch(descriptor).contains { message in
            message.id != MessageServiceSupport.trumpWebPreviewDemoMessageId
        }
    }

    func personaIdsWithConversationHistoryBeyondStarter(
        for personaIds: [String],
        modelContext: ModelContext
    ) throws -> Set<String> {
        let dedupedPersonaIds = Array(NSOrderedSet(array: personaIds)) as? [String] ?? personaIds
        guard !dedupedPersonaIds.isEmpty else { return [] }

        let descriptor = FetchDescriptor<PersonaMessage>(
            predicate: #Predicate<PersonaMessage> { dedupedPersonaIds.contains($0.threadId) && $0.isSeedMessage == false }
        )
        let messages = try modelContext.fetch(descriptor)
        return Set(
            messages.compactMap { message in
                message.id == MessageServiceSupport.trumpWebPreviewDemoMessageId ? nil : message.threadId
            }
        )
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
