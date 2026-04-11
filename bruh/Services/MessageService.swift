import Foundation
import SwiftData

@MainActor
final class MessageService {
    enum StarterRefreshOutcome {
        case remoteUpdated
        case localFallbackOnly

        var didLoadRemoteData: Bool {
            switch self {
            case .remoteUpdated:
                return true
            case .localFallbackOnly:
                return false
            }
        }
    }

    private let api: APIClient
    private let threadStore: MessageThreadStore
    private let starterLifecycle: StarterMessageLifecycle

    init(
        api: APIClient = APIClient(),
        runtimeOptions: AppRuntimeOptions = .current
    ) {
        self.api = api
        let threadStore = MessageThreadStore()
        self.threadStore = threadStore
        self.starterLifecycle = StarterMessageLifecycle(
            api: api,
            runtimeOptions: runtimeOptions,
            threadStore: threadStore
        )
    }

    func prepareThreads(modelContext: ModelContext) throws {
        let acceptedPersonaIds = try threadStore.acceptedPersonaIds(modelContext: modelContext)
        _ = try threadStore.ensureThreads(for: acceptedPersonaIds, modelContext: modelContext)

        try starterLifecycle.seedFallbackStarterMessagesIfNeeded(modelContext: modelContext)
        try starterLifecycle.ensureTrumpWebPreviewExample(modelContext: modelContext)
        try starterLifecycle.normalizeStarterMessagesIfNeeded(modelContext: modelContext)

        if modelContext.hasChanges {
            try modelContext.save()
        }
    }

    @discardableResult
    func refreshStarterMessages(modelContext: ModelContext, userInterests: [String]) async -> StarterRefreshOutcome {
        var outcome: StarterRefreshOutcome = .localFallbackOnly

        do {
            try await starterLifecycle.syncStarterMessagesFromRemote(
                modelContext: modelContext,
                userInterests: userInterests
            )
            outcome = .remoteUpdated
        } catch {
            // Keep the locally seeded threads/messages as the fast-path when the starter API is slow or unavailable.
        }

        if modelContext.hasChanges {
            try? modelContext.save()
        }

        return outcome
    }

    func ensureThreadsExist(modelContext: ModelContext, userInterests: [String]) async throws {
        try prepareThreads(modelContext: modelContext)
        _ = await refreshStarterMessages(modelContext: modelContext, userInterests: userInterests)
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
        guard try threadStore.acceptedPersonaIds(modelContext: modelContext).contains(personaId) else { return }
        let wantsImage = requestImage || shouldRequestImage(for: trimmed)

        let thread = try threadStore.ensureThread(for: personaId, modelContext: modelContext)
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
        threadStore.updateThread(thread, preview: trimmed, at: outgoing.createdAt, unreadCount: 0)
        try modelContext.save()

        do {
            let forceVoice = try threadStore.shouldForceVoiceReply(for: thread.id, modelContext: modelContext)
            let reply = try await api.sendMessage(
                personaId: personaId,
                userMessage: trimmed,
                conversation: try threadStore.recentConversation(for: thread.id, modelContext: modelContext),
                userInterests: userInterests,
                requestImage: wantsImage,
                forceVoice: forceVoice
            )

            outgoing.deliveryState = "sent"
            let replyPreview = MessageServiceSupport.messagePreview(
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
            threadStore.updateThread(thread, preview: replyPreview, at: reply.generatedAt, unreadCount: 0)
            try modelContext.save()
        } catch {
            outgoing.deliveryState = "failed"
            try modelContext.save()
            throw error
        }
    }

    func messageTurns(for threadId: String, modelContext: ModelContext, limit: Int = 6) throws -> [MessageTurnDTO] {
        try threadStore.recentConversation(for: threadId, modelContext: modelContext, limit: limit)
    }

    func markThreadRead(personaId: String, modelContext: ModelContext) throws {
        let thread = try threadStore.ensureThread(for: personaId, modelContext: modelContext)
        let latestIncomingAt = try threadStore.latestIncomingMessageDate(for: personaId, modelContext: modelContext)
        MessageThreadReadState.markRead(thread: thread, at: latestIncomingAt)
        if modelContext.hasChanges {
            try modelContext.save()
        }
    }

    private func shouldRequestImage(for text: String) -> Bool {
        let lower = text.lowercased()
        let triggers = [
            "生成", "生图", "图片", "图像", "画", "插画", "海报", "壁纸", "封面", "render", "image", "illustration",
        ]
        return triggers.contains(where: { lower.contains($0) })
    }
}
