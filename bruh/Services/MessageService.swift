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
        if let latestIncomingAt {
            MessageReadStateStore.markRead(personaId: personaId, at: latestIncomingAt)
        }
        thread.unreadCount = 0
        thread.updatedAt = .now
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

        let sortedStarters = reply.starters.sorted { left, right in
            if left.personaId == right.personaId {
                return left.createdAt < right.createdAt
            }
            return left.personaId < right.personaId
        }

        for starter in sortedStarters {
            guard acceptedPersonaIds.contains(starter.personaId) else { continue }
            let thread = try ensureThread(for: starter.personaId, modelContext: modelContext)
            let starterSourceUrl = starter.sourceUrl ?? starter.articleUrl
            let messageId = starter.id
            var descriptor = FetchDescriptor<PersonaMessage>(
                predicate: #Predicate { $0.id == messageId }
            )
            descriptor.fetchLimit = 1

            if let existing = try modelContext.fetch(descriptor).first {
                guard existing.isSeedMessage else { continue }

                let previousText = existing.text
                let previousCreatedAt = existing.createdAt
                existing.threadId = starter.personaId
                existing.personaId = starter.personaId
                existing.text = starter.text
                existing.imageUrl = starter.imageUrl
                existing.sourceUrl = starterSourceUrl
                existing.createdAt = starter.createdAt
                existing.deliveryState = "sent"
                existing.sourcePostIds = starter.sourcePostIds
                ContentGraphStore.syncIncomingMessage(existing, in: modelContext)
                let starterPreview = messagePreview(text: starter.text, imageUrl: starter.imageUrl)

                let shouldRefreshPreview =
                    (thread.lastMessagePreview == previousText && thread.lastMessageAt == previousCreatedAt) ||
                    thread.lastMessageAt < starter.createdAt

                if shouldRefreshPreview {
                    updateThread(thread, preview: starterPreview, at: starter.createdAt, unreadCount: thread.unreadCount)
                }
            } else {
                let starterPreview = messagePreview(text: starter.text, imageUrl: starter.imageUrl)
                let message = PersonaMessage(
                    id: starter.id,
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
                let nextUnreadCount = thread.unreadCount + 1
                updateThread(thread, preview: starterPreview, at: starter.createdAt, unreadCount: nextUnreadCount)
            }
        }

        try seedFallbackStarterMessagesIfNeeded(modelContext: modelContext)
    }

    private func seedFallbackStarterMessagesIfNeeded(modelContext: ModelContext) throws {
        for personaId in try acceptedPersonaIds(modelContext: modelContext) {
            let thread = try ensureThread(for: personaId, modelContext: modelContext)
            let threadId = personaId

            var descriptor = FetchDescriptor<PersonaMessage>(
                predicate: #Predicate { $0.threadId == threadId }
            )
            descriptor.fetchLimit = 1

            if try modelContext.fetch(descriptor).isEmpty {
                let starter = PersonaMessage(
                    id: "starter-\(personaId)",
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
                updateThread(thread, preview: starter.text, at: starter.createdAt, unreadCount: 1)
            }
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
            isSeedMessage: true
        )
        modelContext.insert(demo)
        ContentGraphStore.syncIncomingMessage(demo, in: modelContext)

        if demoDate >= thread.lastMessageAt {
            updateThread(thread, preview: demoText, at: demoDate, unreadCount: max(thread.unreadCount, 1))
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
}

enum MessageReadStateStore {
    private static let defaults = UserDefaults.standard
    private static let keyPrefix = "message.lastReadAt."

    static func lastReadAt(for personaId: String) -> Date? {
        let interval = defaults.double(forKey: key(for: personaId))
        guard interval > 0 else { return nil }
        return Date(timeIntervalSince1970: interval)
    }

    static func markRead(personaId: String, at date: Date) {
        let existing = lastReadAt(for: personaId) ?? .distantPast
        guard date > existing else { return }
        defaults.set(date.timeIntervalSince1970, forKey: key(for: personaId))
    }

    static func unreadCount(
        for personaId: String,
        deliveries: [ContentDelivery],
        fallbackCount: Int = 0
    ) -> Int {
        let threadDeliveries = deliveries.filter { $0.personaId == personaId }
        guard !threadDeliveries.isEmpty else { return max(0, fallbackCount) }

        let cutoff = lastReadAt(for: personaId) ?? .distantPast
        return threadDeliveries.reduce(0) { count, delivery in
            count + (delivery.sortDate > cutoff ? 1 : 0)
        }
    }

    private static func key(for personaId: String) -> String {
        "\(keyPrefix)\(personaId)"
    }
}
