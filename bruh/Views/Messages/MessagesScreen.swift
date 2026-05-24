import Foundation
import SwiftUI
import SwiftData
import UIKit

struct MessagesScreen: View {
    private struct PersonaPresentation {
        let name: String
        let tint: Color
        let avatarName: String
    }

    @Query(sort: [SortDescriptor(\ContentDelivery.sortDate, order: .reverse)]) private var deliveries: [ContentDelivery]
    @Query(sort: [SortDescriptor(\PersonaMessage.createdAt, order: .reverse)]) private var recentMessages: [PersonaMessage]
    let threads: [MessageThread]
    let contacts: [Contact]
    let service: MessageService
    let backgroundColor: Color
    @State private var searchText = ""

    private var visibleThreads: [MessageThread] {
        threads
            .filter { acceptedPersonaIds.contains($0.personaId) }
            .sorted { left, right in
                latestActivityDate(for: left) > latestActivityDate(for: right)
            }
    }

    private var filteredThreads: [MessageThread] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return visibleThreads }

        return visibleThreads.filter { thread in
            let personaName = MessagePersonaHelper.persona(for: thread.personaId, contacts: contacts).name
            return personaName.localizedCaseInsensitiveContains(query)
                || latestPreview(for: thread).localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        let isSearching = !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        ZStack {
            backgroundColor.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 14) {
                    if filteredThreads.isEmpty {
                        ContentUnavailableView(
                            isSearching ? "没有搜索结果" : "还没有消息",
                            systemImage: isSearching ? "magnifyingglass" : "message",
                            description: Text(
                                isSearching
                                    ? "试试搜索其他联系人或聊天内容。"
                                    : "等鸽们先给你发来第一条消息。"
                            )
                        )
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 20)
                        .padding(.top, 44)
                    } else {
                        VStack(spacing: 0) {
                            ForEach(Array(filteredThreads.enumerated()), id: \.element.id) { index, thread in
                                NavigationLink {
                                    MessageDetailView(thread: thread, service: service)
                                } label: {
                                    messageRow(thread: thread)
                                }
                                .buttonStyle(.plain)

                                if index < filteredThreads.count - 1 {
                                    divider
                                }
                            }
                        }
                        .background(Color.white.opacity(0.4))
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .padding(.horizontal, 16)
                    }
                }
                .padding(.top, 10)
                .padding(.bottom, 20)
            }
        }
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always))
        .navigationTitle("消息")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.black.opacity(0.06))
            .frame(height: 0.5)
            .padding(.leading, 74)
    }

    private func messageRow(thread: MessageThread) -> some View {
        let persona = MessagePersonaHelper.persona(for: thread.personaId, contacts: contacts)
        let unreadCount = unreadCount(for: thread)
        let latestActivity = latestActivityDate(for: thread)
        let preview = latestPreview(for: thread)

        return HStack(spacing: 12) {
            avatarCircle(for: thread.personaId, size: 50)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(persona.name)
                        .font(.system(size: 16, weight: unreadCount > 0 ? .semibold : .regular))
                        .foregroundStyle(.primary)
                    Spacer()
                    Text(relativeTime(latestActivity))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Text(preview)
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Spacer()

                    if unreadCount > 0 {
                        Text("\(unreadCount)")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Color.blue)
                            .clipShape(Capsule())
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private func avatarCircle(for personaId: String, size: CGFloat) -> some View {
        let persona = personaPresentation(for: personaId)

        return Circle()
            .fill(persona.tint.opacity(0.18))
            .frame(width: size, height: size)
            .overlay {
                if !persona.avatarName.isEmpty, UIImage(named: persona.avatarName) != nil {
                    Image(persona.avatarName)
                        .resizable()
                        .scaledToFill()
                        .frame(width: size, height: size)
                        .clipShape(Circle())
                } else {
                    Text(String(persona.name.prefix(1)))
                        .font(.system(size: max(12, size * 0.42), weight: .semibold))
                        .foregroundStyle(persona.tint)
                }
            }
    }

    private func relativeTime(_ date: Date) -> String {
        guard date > Date.distantPast else { return "刚刚" }

        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private var acceptedPersonaIds: Set<String> {
        ContentGraphSelectors.acceptedPersonaIds(from: contacts)
    }

    private var contactByPersonaId: [String: Contact] {
        Dictionary(
            contacts.compactMap { contact in
                guard let personaId = contact.linkedPersonaId else { return nil }
                return (personaId, contact)
            },
            uniquingKeysWith: { first, _ in first }
        )
    }

    private var messageDeliveries: [ContentDelivery] {
        ContentGraphSelectors.visibleMessageDeliveries(
            from: deliveries,
            contacts: contacts
        )
    }

    private var canonicalThreadIdByLookupKey: [String: String] {
        var threadIdsByLookupKey: [String: String] = [:]

        for thread in threads {
            for key in threadLookupKeys(for: thread) where threadIdsByLookupKey[key] == nil {
                threadIdsByLookupKey[key] = thread.id
            }
        }

        return threadIdsByLookupKey
    }

    private var latestMessageByThreadId: [String: PersonaMessage] {
        var messagesByThreadId: [String: PersonaMessage] = [:]

        for message in recentMessages {
            guard let threadId = normalizedLookupKey(message.threadId),
                  messagesByThreadId[threadId] == nil else {
                continue
            }
            messagesByThreadId[threadId] = message
        }

        return messagesByThreadId
    }

    private var latestDeliveryByThreadId: [String: ContentDelivery] {
        var deliveriesByThreadId: [String: ContentDelivery] = [:]

        for delivery in messageDeliveries {
            guard let threadId = canonicalThreadId(for: delivery),
                  deliveriesByThreadId[threadId] == nil else {
                continue
            }
            deliveriesByThreadId[threadId] = delivery
        }

        return deliveriesByThreadId
    }

    private var unreadCountByThreadId: [String: Int] {
        MessageThreadReadState.unreadCountsByThreadId(
            threads: threads,
            deliveries: messageDeliveries
        )
    }

    private func personaPresentation(for personaId: String) -> PersonaPresentation {
        if let contact = contactByPersonaId[personaId] {
            return PersonaPresentation(
                name: contact.name,
                tint: AppTheme.color(from: contact.themeColorHex, fallback: MessagePersonaHelper.fallbackTint(for: personaId)),
                avatarName: contact.avatarName
            )
        }

        return PersonaPresentation(
            name: personaId.capitalized,
            tint: MessagePersonaHelper.fallbackTint(for: personaId),
            avatarName: ""
        )
    }

    private func threadLookupKeys(for thread: MessageThread) -> [String] {
        uniqueLookupKeys([thread.id, thread.personaId])
    }

    private func deliveryLookupKeys(for delivery: ContentDelivery) -> [String] {
        uniqueLookupKeys([delivery.threadId, delivery.personaId])
    }

    private func canonicalThreadId(for delivery: ContentDelivery) -> String? {
        for key in deliveryLookupKeys(for: delivery) {
            if let threadId = canonicalThreadIdByLookupKey[key] {
                return threadId
            }
        }
        return nil
    }

    private func uniqueLookupKeys(_ rawValues: [String?]) -> [String] {
        var seen: Set<String> = []
        var keys: [String] = []

        for rawValue in rawValues {
            guard let key = normalizedLookupKey(rawValue), seen.insert(key).inserted else {
                continue
            }
            keys.append(key)
        }

        return keys
    }

    private func normalizedLookupKey(_ rawValue: String?) -> String? {
        guard let rawValue = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawValue.isEmpty else {
            return nil
        }
        return rawValue
    }

    private func latestMessageDelivery(for thread: MessageThread) -> ContentDelivery? {
        latestDeliveryByThreadId[thread.id]
    }

    private func latestPersistedMessage(for thread: MessageThread) -> PersonaMessage? {
        latestMessageByThreadId[thread.id]
    }

    private func latestPreview(for thread: MessageThread) -> String {
        if let message = latestPersistedMessage(for: thread) {
            let preview = messagePreview(for: message)
            if !preview.isEmpty {
                return preview
            }
        }

        let preview = thread.lastMessagePreview.trimmingCharacters(in: .whitespacesAndNewlines)
        if !preview.isEmpty {
            return preview
        }
        if let preview = latestMessageDelivery(for: thread)?.previewText,
           !preview.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return preview
        }
        return "开始聊天"
    }

    private func latestActivityDate(for thread: MessageThread) -> Date {
        let latestMessageDate = latestPersistedMessage(for: thread)?.createdAt ?? .distantPast
        let latestDeliveryDate = latestMessageDelivery(for: thread)?.sortDate ?? .distantPast
        return max(thread.lastMessageAt, max(latestMessageDate, latestDeliveryDate))
    }

    private func unreadCount(for thread: MessageThread) -> Int {
        unreadCountByThreadId[thread.id] ?? max(0, thread.unreadCount)
    }

    private func messagePreview(for message: PersonaMessage) -> String {
        MessageServiceSupport.messagePreview(
            text: message.text,
            imageUrl: message.imageUrl,
            audioUrl: message.audioUrl,
            audioOnly: message.audioOnly
        )
    }
}

private enum MessagesScreenPreviewData {
    static let contacts: [Contact] = [
        Contact(
            linkedPersonaId: "trump",
            name: "Donald Trump",
            phoneNumber: "+1 561 555 0145",
            email: "donald@truthsocial.com",
            avatarName: "avatar_trump",
            locationLabel: "海湖庄园",
            isFavorite: true
        ),
        Contact(
            linkedPersonaId: "musk",
            name: "Elon Musk",
            phoneNumber: "+1 310 555 0142",
            email: "elon@x.ai",
            avatarName: "avatar_musk",
            locationLabel: "X HQ",
            isFavorite: true
        ),
    ]

    static let threads: [MessageThread] = [
        MessageThread(
            id: "trump",
            personaId: "trump",
            lastMessagePreview: "Markets looking very good today.",
            lastMessageAt: Date().addingTimeInterval(-8 * 60),
            unreadCount: 3
        ),
        MessageThread(
            id: "musk",
            personaId: "musk",
            lastMessagePreview: "Just launched 40 Starlinks.",
            lastMessageAt: Date().addingTimeInterval(-15 * 60),
            unreadCount: 1
        ),
    ]

    static let container: ModelContainer = {
        let container = try! ModelContainer(
            for: Contact.self,
            MessageThread.self,
            PersonaMessage.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )

        let context = ModelContext(container)

        contacts.forEach { context.insert($0) }

        let seedMessages: [PersonaMessage] = [
            PersonaMessage(
                id: "preview-1",
                threadId: "trump",
                personaId: "trump",
                text: "Good morning bruh. Markets looking VERY good today.",
                isIncoming: true,
                createdAt: Date().addingTimeInterval(-12 * 60)
            ),
            PersonaMessage(
                id: "preview-2",
                threadId: "trump",
                personaId: "trump",
                text: "What's happening with the tariffs?",
                isIncoming: false,
                createdAt: Date().addingTimeInterval(-11 * 60)
            ),
            PersonaMessage(
                id: "preview-3",
                threadId: "trump",
                personaId: "trump",
                text: "GREAT question bruh! We just slapped 125% tariffs.",
                isIncoming: true,
                createdAt: Date().addingTimeInterval(-10 * 60)
            ),
            PersonaMessage(
                id: "preview-4",
                threadId: "trump",
                personaId: "trump",
                text: "https://www.reuters.com/world/asia-pacific/trump-agrees-two-week-ceasefire-iran-says-safe-passage-through-hormuz-possible-2026-04-08/",
                isIncoming: true,
                createdAt: Date().addingTimeInterval(-9 * 60)
            ),
        ]

        seedMessages.forEach { context.insert($0) }
        try? context.save()

        return container
    }()
}

#Preview("Messages List") {
    NavigationStack {
        MessagesScreen(
            threads: MessagesScreenPreviewData.threads,
            contacts: MessagesScreenPreviewData.contacts,
            service: MessageService(),
            backgroundColor: AppTheme.messagesBackground
        )
    }
    .modelContainer(MessagesScreenPreviewData.container)
}

#Preview("Message Detail") {
    NavigationStack {
        MessageDetailView(
            thread: MessagesScreenPreviewData.threads[0],
            service: MessageService()
        )
    }
    .modelContainer(MessagesScreenPreviewData.container)
}
