import Foundation
import SwiftData

@MainActor
final class MessageService {
    private let api: APIClient

    init(api: APIClient = APIClient()) {
        self.api = api
    }

    func ensureThreadsExist(modelContext: ModelContext, userInterests: [String]) async throws {
        for persona in Persona.all {
            let thread = try ensureThread(for: persona.id, modelContext: modelContext)
            _ = thread
        }

        try seedFallbackStarterMessagesIfNeeded(modelContext: modelContext)
        try ensureTrumpWebPreviewExample(modelContext: modelContext)

        if modelContext.hasChanges {
            try modelContext.save()
        }

        do {
            try await syncStarterMessages(modelContext: modelContext, userInterests: userInterests)
        } catch {
            // Keep the locally seeded threads/messages as the fast-path when the starter API is slow or unavailable.
        }

        if modelContext.hasChanges {
            try modelContext.save()
        }
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
            let replyPreview = messagePreview(text: reply.content, imageUrl: reply.imageUrl)
            let incoming = PersonaMessage(
                id: reply.id,
                threadId: thread.id,
                personaId: personaId,
                text: reply.content,
                imageUrl: reply.imageUrl,
                isIncoming: true,
                createdAt: reply.generatedAt,
                deliveryState: "sent",
                sourcePostIds: reply.sourcePostIds
            )
            modelContext.insert(incoming)
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
        thread.unreadCount = 0
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

    private func syncStarterMessages(modelContext: ModelContext, userInterests: [String]) async throws {
        let reply = try await api.fetchMessageStarters(userInterests: userInterests)

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
            let thread = try ensureThread(for: starter.personaId, modelContext: modelContext)
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
                existing.createdAt = starter.createdAt
                existing.deliveryState = "sent"
                existing.sourcePostIds = starter.sourcePostIds

                let shouldRefreshPreview =
                    (thread.lastMessagePreview == previousText && thread.lastMessageAt == previousCreatedAt) ||
                    thread.lastMessageAt < starter.createdAt

                if shouldRefreshPreview {
                    updateThread(thread, preview: starter.text, at: starter.createdAt, unreadCount: thread.unreadCount)
                }
            } else {
                let message = PersonaMessage(
                    id: starter.id,
                    threadId: starter.personaId,
                    personaId: starter.personaId,
                    text: starter.text,
                    isIncoming: true,
                    createdAt: starter.createdAt,
                    deliveryState: "sent",
                    sourcePostIds: starter.sourcePostIds,
                    isSeedMessage: true
                )
                modelContext.insert(message)
                let nextUnreadCount = thread.unreadCount + 1
                updateThread(thread, preview: starter.text, at: starter.createdAt, unreadCount: nextUnreadCount)
            }
        }

        try seedFallbackStarterMessagesIfNeeded(modelContext: modelContext)
    }

    private func seedFallbackStarterMessagesIfNeeded(modelContext: ModelContext) throws {
        for persona in Persona.all {
            let thread = try ensureThread(for: persona.id, modelContext: modelContext)
            let threadId = persona.id

            var descriptor = FetchDescriptor<PersonaMessage>(
                predicate: #Predicate { $0.threadId == threadId }
            )
            descriptor.fetchLimit = 1

            if try modelContext.fetch(descriptor).isEmpty {
                let starter = PersonaMessage(
                    id: "starter-\(persona.id)",
                    threadId: persona.id,
                    personaId: persona.id,
                    text: starterMessage(for: persona.id),
                    isIncoming: true,
                    createdAt: Date(),
                    deliveryState: "sent",
                    isSeedMessage: true
                )
                modelContext.insert(starter)
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

    private func messagePreview(text: String, imageUrl: String?) -> String {
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
        switch personaId {
        case "musk":
            return "Saw a few interesting AI and space signals today. What caught your eye?"
        case "trump":
            return "Big stories today. Trade, politics, the usual chaos. What do you want to talk about?"
        case "zuckerberg":
            return "A lot happening across AI and social. Want the short version or the spicy version?"
        default:
            return "What do you want to talk about today?"
        }
    }

    private func ensureTrumpWebPreviewExample(modelContext: ModelContext) throws {
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

        if demoDate >= thread.lastMessageAt {
            updateThread(thread, preview: demoText, at: demoDate, unreadCount: max(thread.unreadCount, 1))
        }
    }
}
