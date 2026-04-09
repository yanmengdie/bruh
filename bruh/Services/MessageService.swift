import Foundation
import SwiftData

@MainActor
final class MessageService {
    private let api: APIClient

    init(api: APIClient = APIClient()) {
        self.api = api
    }

    func prepareThreads(modelContext: ModelContext) throws {
        for personaId in try acceptedPersonaIds(modelContext: modelContext) {
            let thread = try ensureThread(for: personaId, modelContext: modelContext)
            _ = thread
        }

        try seedFallbackStarterMessagesIfNeeded(modelContext: modelContext)
        try ensureTrumpWebPreviewExample(modelContext: modelContext)
        try normalizeStarterMessagesIfNeeded(modelContext: modelContext)

        if modelContext.hasChanges {
            try modelContext.save()
        }
    }

    func refreshStarterMessages(modelContext: ModelContext, userInterests: [String]) async {
        do {
            try await syncStarterMessagesFromRemote(modelContext: modelContext, userInterests: userInterests)
        } catch {
            // Keep the locally seeded threads/messages as the fast-path when the starter API is slow or unavailable.
        }

        if modelContext.hasChanges {
            try? modelContext.save()
        }
    }

    func ensureThreadsExist(modelContext: ModelContext, userInterests: [String]) async throws {
        try prepareThreads(modelContext: modelContext)
        await refreshStarterMessages(modelContext: modelContext, userInterests: userInterests)
    }

    func sendMessage(
        personaId: String,
        text: String,
        modelContext: ModelContext,
        userInterests: [String],
        requestImage: Bool = false
    ) async throws {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard try acceptedPersonaIds(modelContext: modelContext).contains(personaId) else { return }
        let wantsImage = requestImage || shouldRequestImage(for: trimmed)

        let thread = try ensureThread(for: personaId, modelContext: modelContext)
        let outgoing = PersonaMessage(
            id: UUID().uuidString,
            threadId: thread.id,
            personaId: personaId,
            text: trimmed,
            isIncoming: false,
            createdAt: Date(),
            deliveryState: "sending"
        )
        modelContext.insert(outgoing)
        updateThread(thread, preview: trimmed, at: outgoing.createdAt, unreadCount: 0)
        try modelContext.save()

        do {
            let reply = try await api.sendMessage(
                personaId: personaId,
                userMessage: trimmed,
                conversation: try recentConversation(for: thread.id, modelContext: modelContext),
                userInterests: userInterests,
                requestImage: wantsImage
            )

            outgoing.deliveryState = "sent"
            let replyPreview = messagePreview(
                text: reply.content,
                imageUrl: reply.imageUrl,
                audioUrl: reply.audioUrl,
                audioOnly: reply.audioOnly == true
            )
            let incoming = PersonaMessage(
                id: reply.id,
                threadId: thread.id,
                personaId: personaId,
                text: reply.content,
                imageUrl: reply.imageUrl,
                sourceUrl: reply.sourceUrl,
                audioUrl: reply.audioUrl,
                audioDuration: reply.audioDuration,
                voiceLabel: reply.voiceLabel,
                audioError: reply.audioError,
                audioOnly: reply.audioOnly == true,
                isIncoming: true,
                createdAt: reply.generatedAt,
                deliveryState: "sent",
                sourcePostIds: reply.sourcePostIds
            )
            modelContext.insert(incoming)
            ContentGraphStore.syncIncomingMessage(incoming, in: modelContext)
            updateThread(thread, preview: replyPreview, at: reply.generatedAt, unreadCount: 0)
            try modelContext.save()
        } catch {
            outgoing.deliveryState = "failed"
            try modelContext.save()
            throw error
        }
    }

    func messageTurns(for threadId: String, modelContext: ModelContext, limit: Int = 6) throws -> [MessageTurnDTO] {
        try recentConversation(for: threadId, modelContext: modelContext, limit: limit)
    }

    func markThreadRead(personaId: String, modelContext: ModelContext) throws {
        let thread = try ensureThread(for: personaId, modelContext: modelContext)
        let latestIncomingAt = try latestIncomingMessageDate(for: personaId, modelContext: modelContext)
        MessageThreadReadState.markRead(thread: thread, at: latestIncomingAt)
        if modelContext.hasChanges {
            try modelContext.save()
        }
    }

    private func ensureThread(for personaId: String, modelContext: ModelContext) throws -> MessageThread {
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
            lastMessageAt: Date.distantPast,
            unreadCount: 0
        )
        modelContext.insert(thread)
        return thread
    }

    private func syncStarterMessagesFromRemote(modelContext: ModelContext, userInterests: [String]) async throws {
        let reply = try await api.fetchMessageStarters(userInterests: userInterests)
        let acceptedPersonaIds = Set(try acceptedPersonaIds(modelContext: modelContext))

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
            let thread = try ensureThread(for: starter.personaId, modelContext: modelContext)
            guard try !hasConversationHistoryBeyondStarter(for: starter.personaId, modelContext: modelContext) else {
                continue
            }

            let starterSourceUrl = starter.sourceUrl ?? starter.articleUrl
            let starterPreview = messagePreview(text: starter.text, imageUrl: starter.imageUrl)

            if let existing = try starterMessage(for: starter.personaId, modelContext: modelContext) {
                let previousPreview = messagePreview(
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
                existing.sourceUrl = starterSourceUrl
                existing.deliveryState = "sent"
                existing.sourcePostIds = starter.sourcePostIds
                existing.isSeedMessage = true
                ContentGraphStore.syncIncomingMessage(existing, in: modelContext)

                let shouldRefreshPreview =
                    (thread.lastMessagePreview == previousText && thread.lastMessageAt == previousCreatedAt) ||
                    (thread.lastMessagePreview == previousPreview && thread.lastMessageAt == previousCreatedAt)

                if shouldRefreshPreview {
                    updateThread(thread, preview: starterPreview, at: previousCreatedAt, unreadCount: thread.unreadCount)
                }
            } else {
                let message = PersonaMessage(
                    id: starterMessageId(for: starter.personaId),
                    threadId: starter.personaId,
                    personaId: starter.personaId,
                    text: starter.text,
                    imageUrl: starter.imageUrl,
                    sourceUrl: starterSourceUrl,
                    isIncoming: true,
                    createdAt: starter.createdAt,
                    deliveryState: "sent",
                    sourcePostIds: starter.sourcePostIds,
                    isSeedMessage: true
                )
                modelContext.insert(message)
                ContentGraphStore.syncIncomingMessage(message, in: modelContext)
                let nextUnreadCount = nextUnreadCount(afterReceivingMessageAt: starter.createdAt, on: thread)
                updateThread(thread, preview: starterPreview, at: starter.createdAt, unreadCount: nextUnreadCount)
            }
        }

        try normalizeStarterMessagesIfNeeded(modelContext: modelContext)
        try seedFallbackStarterMessagesIfNeeded(modelContext: modelContext)
    }

    private func seedFallbackStarterMessagesIfNeeded(modelContext: ModelContext) throws {
        for personaId in try acceptedPersonaIds(modelContext: modelContext) {
            let thread = try ensureThread(for: personaId, modelContext: modelContext)
            guard try starterMessage(for: personaId, modelContext: modelContext) == nil else {
                continue
            }
            guard try !hasConversationHistoryBeyondStarter(for: personaId, modelContext: modelContext) else {
                continue
            }

            let starter = PersonaMessage(
                id: starterMessageId(for: personaId),
                threadId: personaId,
                personaId: personaId,
                text: starterMessage(for: personaId),
                isIncoming: true,
                createdAt: Date(),
                deliveryState: "sent",
                isSeedMessage: true
            )
            modelContext.insert(starter)
            ContentGraphStore.syncIncomingMessage(starter, in: modelContext)
            let nextUnreadCount = nextUnreadCount(afterReceivingMessageAt: starter.createdAt, on: thread)
            updateThread(thread, preview: starter.text, at: starter.createdAt, unreadCount: nextUnreadCount)
        }
    }

    private func recentConversation(
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

    private func updateThread(_ thread: MessageThread, preview: String, at date: Date, unreadCount: Int) {
        thread.lastMessagePreview = preview
        thread.lastMessageAt = date
        thread.updatedAt = Date()
        thread.unreadCount = unreadCount
    }

    private func messagePreview(
        text: String,
        imageUrl: String?,
        audioUrl: String? = nil,
        audioOnly: Bool = false
    ) -> String {
        if audioOnly, let audioUrl, !audioUrl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "[Voice]"
        }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard imageUrl != nil else { return trimmed }
        return trimmed.isEmpty ? "[图片]" : "[图片] \(trimmed)"
    }

    private func shouldRequestImage(for text: String) -> Bool {
        let lower = text.lowercased()
        let triggers = [
            "生成", "生图", "图片", "图像", "画", "插画", "海报", "壁纸", "封面", "render", "image", "illustration",
        ]
        return triggers.contains(where: { lower.contains($0) })
    }

    private func starterMessage(for personaId: String) -> String {
        PersonaCatalog.starterMessage(for: personaId)
    }

    private func starterMessageId(for personaId: String) -> String {
        "starter:\(personaId)"
    }

    private func ensureTrumpWebPreviewExample(modelContext: ModelContext) throws {
        guard try acceptedPersonaIds(modelContext: modelContext).contains("trump") else { return }
        let demoId = "seed-trump-reuters-og"
        var messageDescriptor = FetchDescriptor<PersonaMessage>(
            predicate: #Predicate { $0.id == demoId }
        )
        messageDescriptor.fetchLimit = 1

        if try modelContext.fetch(messageDescriptor).first != nil {
            return
        }

        let thread = try ensureThread(for: "trump", modelContext: modelContext)
        let demoDate = Date().addingTimeInterval(-60)
        let demoText = "https://www.reuters.com/world/asia-pacific/trump-agrees-two-week-ceasefire-iran-says-safe-passage-through-hormuz-possible-2026-04-08/"
        let demo = PersonaMessage(
            id: demoId,
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
            let nextUnreadCount = nextUnreadCount(afterReceivingMessageAt: demoDate, on: thread)
            updateThread(thread, preview: demoText, at: demoDate, unreadCount: nextUnreadCount)
        }
    }

    private func acceptedPersonaIds(modelContext: ModelContext) throws -> [String] {
        let contacts = try modelContext.fetch(FetchDescriptor<Contact>())
        let ids = contacts
            .filter { $0.relationshipStatusValue == .accepted }
            .compactMap(\.linkedPersonaId)
        return Array(NSOrderedSet(array: ids)) as? [String] ?? ids
    }

    private func latestIncomingMessageDate(for personaId: String, modelContext: ModelContext) throws -> Date? {
        let threadId = personaId
        var descriptor = FetchDescriptor<PersonaMessage>(
            predicate: #Predicate { $0.threadId == threadId && $0.isIncoming },
            sortBy: [SortDescriptor(\PersonaMessage.createdAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first?.createdAt
    }

    private func starterMessage(for personaId: String, modelContext: ModelContext) throws -> PersonaMessage? {
        let starterMessages = try starterMessages(for: personaId, modelContext: modelContext)
        if let canonical = starterMessages.first(where: { $0.id == starterMessageId(for: personaId) }) {
            return canonical
        }
        return starterMessages.first
    }

    private func starterMessages(for personaId: String, modelContext: ModelContext) throws -> [PersonaMessage] {
        let descriptor = FetchDescriptor<PersonaMessage>(
            predicate: #Predicate { $0.threadId == personaId && $0.isSeedMessage },
            sortBy: [SortDescriptor(\PersonaMessage.createdAt, order: .forward)]
        )
        return try modelContext.fetch(descriptor)
    }

    private func hasConversationHistoryBeyondStarter(for personaId: String, modelContext: ModelContext) throws -> Bool {
        let descriptor = FetchDescriptor<PersonaMessage>(
            predicate: #Predicate { $0.threadId == personaId && $0.isSeedMessage == false }
        )
        return try modelContext.fetch(descriptor).contains { message in
            message.id != trumpWebPreviewDemoMessageId
        }
    }

    private func normalizeStarterMessagesIfNeeded(modelContext: ModelContext) throws {
        for personaId in try acceptedPersonaIds(modelContext: modelContext) {
            try normalizeStarterMessages(for: personaId, modelContext: modelContext)
        }
    }

    private var trumpWebPreviewDemoMessageId: String {
        "seed-trump-reuters-og"
    }

    private func normalizeStarterMessages(for personaId: String, modelContext: ModelContext) throws {
        let starterMessages = try starterMessages(for: personaId, modelContext: modelContext)
        guard starterMessages.count > 1 else { return }

        let thread = try ensureThread(for: personaId, modelContext: modelContext)
        let keeper = starterMessages.first(where: { $0.id == starterMessageId(for: personaId) }) ?? starterMessages[0]
        let richest = preferredStarterMessage(from: starterMessages)
        let previousCreatedAt = keeper.createdAt
        let earliestCreatedAt = starterMessages.map(\.createdAt).min() ?? keeper.createdAt
        let previousPreview = messagePreview(
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

        let mergedPreview = messagePreview(
            text: keeper.text,
            imageUrl: keeper.imageUrl,
            audioUrl: keeper.audioUrl,
            audioOnly: keeper.audioOnly
        )
        if thread.lastMessageAt == previousCreatedAt || thread.lastMessagePreview == previousPreview {
            updateThread(thread, preview: mergedPreview, at: earliestCreatedAt, unreadCount: thread.unreadCount)
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
        if !(message.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) { score += 1 }
        if let sourceUrl = message.sourceUrl?.trimmingCharacters(in: .whitespacesAndNewlines), !sourceUrl.isEmpty { score += 2 }
        if message.imageUrl != nil { score += 2 }
        if !message.sourcePostIds.isEmpty { score += 3 }
        return score
    }

    private func deleteArtifacts(for message: PersonaMessage, modelContext: ModelContext) throws {
        for deliveryId in ["delivery:message:\(message.id)", "delivery:album:\(message.id)"] {
            if let delivery = try fetchContentDelivery(id: deliveryId, modelContext: modelContext) {
                modelContext.delete(delivery)
            }
        }

        let eventId = message.contentEventId ?? "event:message:\(message.id)"
        if let event = try fetchContentEvent(id: eventId, modelContext: modelContext) {
            modelContext.delete(event)
        }
    }

    private func fetchContentDelivery(id: String, modelContext: ModelContext) throws -> ContentDelivery? {
        var descriptor = FetchDescriptor<ContentDelivery>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    private func fetchContentEvent(id: String, modelContext: ModelContext) throws -> ContentEvent? {
        var descriptor = FetchDescriptor<ContentEvent>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    private func nextUnreadCount(afterReceivingMessageAt date: Date, on thread: MessageThread) -> Int {
        guard date > (thread.lastReadAt ?? .distantPast) else {
            return max(0, thread.unreadCount)
        }
        return max(0, thread.unreadCount) + 1
    }
}

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
