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

        for personaId in latestStarterByPersona.keys.sorted() {
            guard let starter = latestStarterByPersona[personaId] else { continue }
            let thread = try threadStore.ensureThread(for: starter.personaId, modelContext: modelContext)
            guard try !threadStore.hasConversationHistoryBeyondStarter(
                for: starter.personaId,
                modelContext: modelContext
            ) else {
                continue
            }

            let starterPreview = MessageServiceSupport.messagePreview(
                text: starter.text,
                imageUrl: starter.imageUrl
            )

            if let existing = try threadStore.starterMessage(for: starter.personaId, modelContext: modelContext) {
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
                ContentGraphStore.syncIncomingMessage(existing, in: modelContext)

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
                ContentGraphStore.syncIncomingMessage(message, in: modelContext)
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

        try normalizeStarterMessagesIfNeeded(modelContext: modelContext)
        try seedFallbackStarterMessagesIfNeeded(modelContext: modelContext)
    }
}
