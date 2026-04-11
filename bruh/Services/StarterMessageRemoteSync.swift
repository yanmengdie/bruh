import Foundation
import SwiftData

extension StarterMessageLifecycle {
    func syncStarterMessagesFromRemote(modelContext: ModelContext, userInterests: [String]) async throws {
        let reply = try await api.fetchMessageStarters(userInterests: userInterests)
        let acceptedPersonaIds = Set(try threadStore.acceptedPersonaIds(modelContext: modelContext))

        if reply.starters.isEmpty {
            try seedFallbackStarterMessagesIfNeeded(modelContext: modelContext)
            return
        }

        var latestStarterByPersona: [String: MessageStarterDTO] = [:]
        for starter in reply.starters {
            guard acceptedPersonaIds.contains(starter.personaId) else { continue }
            if let existing = latestStarterByPersona[starter.personaId], existing.createdAt >= starter.createdAt {
                continue
            }
            latestStarterByPersona[starter.personaId] = starter
        }

        let personaIds = latestStarterByPersona.keys.sorted()
        let threadsByPersonaId = try threadStore.ensureThreads(for: personaIds, modelContext: modelContext)
        let personaIdsWithConversationHistory = try threadStore.personaIdsWithConversationHistoryBeyondStarter(
            for: personaIds,
            modelContext: modelContext
        )
        let existingStarterByPersona = try threadStore.canonicalStarterMessagesByPersonaId(
            for: personaIds,
            modelContext: modelContext
        )
        var messagesToSync: [PersonaMessage] = []

        for personaId in personaIds {
            guard let starter = latestStarterByPersona[personaId] else { continue }
            guard let thread = threadsByPersonaId[starter.personaId] else { continue }
            guard !personaIdsWithConversationHistory.contains(starter.personaId) else {
                continue
            }

            let starterPreview = MessageServiceSupport.messagePreview(
                text: starter.text,
                imageUrl: starter.imageUrl
            )

            if let existing = existingStarterByPersona[starter.personaId] {
                let previousPreview = MessageServiceSupport.messagePreview(
                    text: existing.text,
                    imageUrl: existing.imageUrl,
                    audioUrl: existing.audioUrl,
                    audioOnly: existing.audioOnly
                )
                let previousText = existing.text
                let previousCreatedAt = existing.createdAt
                existing.threadId = starter.personaId
                existing.personaId = starter.personaId
                existing.text = starter.text
                existing.imageUrl = starter.imageUrl
                existing.sourceUrl = starter.sourceUrl
                existing.deliveryState = "sent"
                existing.sourcePostIds = starter.sourcePostIds
                existing.isSeedMessage = true
                messagesToSync.append(existing)

                let shouldRefreshPreview =
                    (thread.lastMessagePreview == previousText && thread.lastMessageAt == previousCreatedAt) ||
                    (thread.lastMessagePreview == previousPreview && thread.lastMessageAt == previousCreatedAt)

                if shouldRefreshPreview {
                    threadStore.updateThread(
                        thread,
                        preview: starterPreview,
                        at: previousCreatedAt,
                        unreadCount: thread.unreadCount
                    )
                }
            } else {
                let message = PersonaMessage(
                    id: MessageServiceSupport.starterMessageId(for: starter.personaId),
                    threadId: starter.personaId,
                    personaId: starter.personaId,
                    text: starter.text,
                    imageUrl: starter.imageUrl,
                    sourceUrl: starter.sourceUrl,
                    isIncoming: true,
                    createdAt: starter.createdAt,
                    deliveryState: "sent",
                    sourcePostIds: starter.sourcePostIds,
                    isSeedMessage: true
                )
                modelContext.insert(message)
                messagesToSync.append(message)
                let nextUnreadCount = threadStore.nextUnreadCount(
                    afterReceivingMessageAt: starter.createdAt,
                    on: thread
                )
                threadStore.updateThread(
                    thread,
                    preview: starterPreview,
                    at: starter.createdAt,
                    unreadCount: nextUnreadCount
                )
            }
        }

        ContentGraphStore.syncIncomingMessages(messagesToSync, in: modelContext)
        try normalizeStarterMessagesIfNeeded(modelContext: modelContext)
        try seedFallbackStarterMessagesIfNeeded(modelContext: modelContext)
    }
}
