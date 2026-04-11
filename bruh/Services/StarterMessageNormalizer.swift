import Foundation
import SwiftData

extension StarterMessageLifecycle {
    func normalizeStarterMessagesIfNeeded(modelContext: ModelContext) throws {
        for personaId in try threadStore.acceptedPersonaIds(modelContext: modelContext) {
            try normalizeStarterMessages(for: personaId, modelContext: modelContext)
        }
    }

    private func normalizeStarterMessages(for personaId: String, modelContext: ModelContext) throws {
        let starterMessages = try threadStore.starterMessages(for: personaId, modelContext: modelContext)
        guard starterMessages.count > 1 else { return }

        let thread = try threadStore.ensureThread(for: personaId, modelContext: modelContext)
        let keeper = starterMessages.first(where: { $0.id == MessageServiceSupport.starterMessageId(for: personaId) })
            ?? starterMessages[0]
        let richest = preferredStarterMessage(from: starterMessages)
        let previousCreatedAt = keeper.createdAt
        let earliestCreatedAt = starterMessages.map(\.createdAt).min() ?? keeper.createdAt
        let previousPreview = MessageServiceSupport.messagePreview(
            text: keeper.text,
            imageUrl: keeper.imageUrl,
            audioUrl: keeper.audioUrl,
            audioOnly: keeper.audioOnly
        )

        keeper.threadId = personaId
        keeper.personaId = personaId
        keeper.text = richest.text
        keeper.imageUrl = richest.imageUrl
        keeper.sourceUrl = richest.sourceUrl
        keeper.audioUrl = richest.audioUrl
        keeper.audioDuration = richest.audioDuration
        keeper.voiceLabel = richest.voiceLabel
        keeper.audioOnly = richest.audioOnly
        keeper.deliveryState = "sent"
        keeper.sourcePostIds = richest.sourcePostIds
        keeper.isSeedMessage = true
        keeper.createdAt = earliestCreatedAt
        ContentGraphStore.syncIncomingMessage(keeper, in: modelContext)

        let mergedPreview = MessageServiceSupport.messagePreview(
            text: keeper.text,
            imageUrl: keeper.imageUrl,
            audioUrl: keeper.audioUrl,
            audioOnly: keeper.audioOnly
        )
        if thread.lastMessageAt == previousCreatedAt || thread.lastMessagePreview == previousPreview {
            threadStore.updateThread(
                thread,
                preview: mergedPreview,
                at: earliestCreatedAt,
                unreadCount: thread.unreadCount
            )
        }

        for duplicate in starterMessages where duplicate.id != keeper.id {
            try deleteArtifacts(for: duplicate, modelContext: modelContext)
            modelContext.delete(duplicate)
        }
    }

    private func preferredStarterMessage(from messages: [PersonaMessage]) -> PersonaMessage {
        messages.max { left, right in
            let leftScore = starterMessageScore(left)
            let rightScore = starterMessageScore(right)
            if leftScore == rightScore {
                return left.createdAt < right.createdAt
            }
            return leftScore < rightScore
        } ?? messages[0]
    }

    private func starterMessageScore(_ message: PersonaMessage) -> Int {
        var score = 0
        if !message.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { score += 1 }
        if let sourceUrl = message.sourceUrl?.trimmingCharacters(in: .whitespacesAndNewlines), !sourceUrl.isEmpty { score += 2 }
        if message.imageUrl != nil { score += 2 }
        if !message.sourcePostIds.isEmpty { score += 3 }
        return score
    }

    private func deleteArtifacts(for message: PersonaMessage, modelContext: ModelContext) throws {
        for deliveryId in ["delivery:message:\(message.id)", "delivery:album:\(message.id)"] {
            if let delivery = try threadStore.fetchContentDelivery(id: deliveryId, modelContext: modelContext) {
                modelContext.delete(delivery)
            }
        }

        let eventId = message.contentEventId ?? "event:message:\(message.id)"
        if let event = try threadStore.fetchContentEvent(id: eventId, modelContext: modelContext) {
            modelContext.delete(event)
        }
    }
}
