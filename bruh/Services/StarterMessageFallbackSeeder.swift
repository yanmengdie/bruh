import Foundation
import SwiftData

extension StarterMessageLifecycle {
    func seedFallbackStarterMessagesIfNeeded(modelContext: ModelContext) throws {
        guard runtimeOptions.shouldSeedFallbackStarters else { return }

        let acceptedPersonaIds = try threadStore.acceptedPersonaIds(modelContext: modelContext)
        let threadsByPersonaId = try threadStore.ensureThreads(for: acceptedPersonaIds, modelContext: modelContext)
        let existingStarterByPersona = try threadStore.canonicalStarterMessagesByPersonaId(
            for: acceptedPersonaIds,
            modelContext: modelContext
        )
        let personaIdsWithConversationHistory = try threadStore.personaIdsWithConversationHistoryBeyondStarter(
            for: acceptedPersonaIds,
            modelContext: modelContext
        )
        var startersToSync: [PersonaMessage] = []

        for personaId in acceptedPersonaIds {
            guard let thread = threadsByPersonaId[personaId] else { continue }
            guard existingStarterByPersona[personaId] == nil else {
                continue
            }
            guard !personaIdsWithConversationHistory.contains(personaId) else {
                continue
            }

            let starter = PersonaMessage(
                id: MessageServiceSupport.starterMessageId(for: personaId),
                threadId: personaId,
                personaId: personaId,
                text: MessageServiceSupport.starterMessageText(for: personaId),
                isIncoming: true,
                createdAt: .now,
                deliveryState: "sent",
                isSeedMessage: true
            )
            modelContext.insert(starter)
            startersToSync.append(starter)
            let nextUnreadCount = threadStore.nextUnreadCount(afterReceivingMessageAt: starter.createdAt, on: thread)
            threadStore.updateThread(
                thread,
                preview: starter.text,
                at: starter.createdAt,
                unreadCount: nextUnreadCount
            )
        }

        ContentGraphStore.syncIncomingMessages(startersToSync, in: modelContext)
    }

    func ensureTrumpWebPreviewExample(modelContext: ModelContext) throws {
        guard runtimeOptions.shouldInjectMessageDemoArtifacts else { return }
        guard try threadStore.acceptedPersonaIds(modelContext: modelContext).contains("trump") else { return }
        let demoMessageId = MessageServiceSupport.trumpWebPreviewDemoMessageId

        var messageDescriptor = FetchDescriptor<PersonaMessage>(
            predicate: #Predicate { $0.id == demoMessageId }
        )
        messageDescriptor.fetchLimit = 1

        if try modelContext.fetch(messageDescriptor).first != nil {
            return
        }

        let thread = try threadStore.ensureThread(for: "trump", modelContext: modelContext)
        let demoDate = Date().addingTimeInterval(-60)
        let demoText = "https://www.reuters.com/world/asia-pacific/trump-agrees-two-week-ceasefire-iran-says-safe-passage-through-hormuz-possible-2026-04-08/"
        let demo = PersonaMessage(
            id: demoMessageId,
            threadId: "trump",
            personaId: "trump",
            text: demoText,
            isIncoming: true,
            createdAt: demoDate,
            deliveryState: "sent",
            isSeedMessage: false
        )
        modelContext.insert(demo)
        ContentGraphStore.syncIncomingMessage(demo, in: modelContext)

        if demoDate >= thread.lastMessageAt {
            let nextUnreadCount = threadStore.nextUnreadCount(afterReceivingMessageAt: demoDate, on: thread)
            threadStore.updateThread(thread, preview: demoText, at: demoDate, unreadCount: nextUnreadCount)
        }
    }
}
