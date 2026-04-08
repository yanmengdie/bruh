import SwiftUI
import SwiftData

struct MessagesScreen: View {
    let threads: [MessageThread]
    let contacts: [Contact]
    let service: MessageService
    let backgroundColor: Color

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                messageSearchBar
                    .padding(.horizontal, 16)

                VStack(spacing: 0) {
                    ForEach(Array(threads.enumerated()), id: \.element.id) { index, thread in
                        NavigationLink {
                            MessageDetailView(thread: thread, service: service)
                        } label: {
                            messageRow(thread: thread)
                        }
                        .buttonStyle(.plain)

                        if index < threads.count - 1 {
                            divider
                        }
                    }
                }
                .background(.white)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .padding(.horizontal, 16)
            }
            .padding(.top, 10)
            .padding(.bottom, 20)
        }
        .background(backgroundColor)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Image(systemName: "plus")
            }
        }
    }

    private var messageSearchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            Text("搜索")
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.black.opacity(0.06))
            .frame(height: 0.5)
            .padding(.leading, 74)
    }

    private func messageRow(thread: MessageThread) -> some View {
        let persona = persona(for: thread.personaId)

        return HStack(spacing: 12) {
            Circle()
                .fill(persona.tint.opacity(0.18))
                .frame(width: 50, height: 50)
                .overlay {
                    Text(String(persona.name.prefix(1)))
                        .font(.headline)
                        .foregroundStyle(persona.tint)
                }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(persona.name)
                        .font(.system(size: 16, weight: thread.unreadCount > 0 ? .semibold : .regular))
                        .foregroundStyle(.primary)
                    Spacer()
                    Text(relativeTime(thread.lastMessageAt))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Text(thread.lastMessagePreview.isEmpty ? "Start the conversation" : thread.lastMessagePreview)
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Spacer()

                    if thread.unreadCount > 0 {
                        Text("\(thread.unreadCount)")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Color.blue)
                            .clipShape(Capsule())
                    }
                }
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private func persona(for personaId: String) -> (name: String, tint: Color) {
        if let contact = contacts.first(where: { $0.linkedPersonaId == personaId }) {
            return (contact.name, AppTheme.color(from: contact.themeColorHex, fallback: fallbackTint(for: personaId)))
        }

        return (personaId.capitalized, fallbackTint(for: personaId))
    }

    private func fallbackTint(for personaId: String) -> Color {
        switch personaId {
        case "trump":
            return .orange
        case "musk":
            return .blue
        case "zuckerberg":
            return .purple
        default:
            return .gray
        }
    }

    private func relativeTime(_ date: Date) -> String {
        guard date > Date.distantPast else { return "Now" }

        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

private struct MessageDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var messages: [PersonaMessage]
    @Query(sort: [SortDescriptor(\Contact.name, order: .forward)]) private var contacts: [Contact]

    let thread: MessageThread
    let service: MessageService

    @State private var draft = ""
    @State private var isSending = false
    @State private var errorMessage: String?
    @State private var selectedQuickReactions: [String: String] = [:]
    private let quickReactionOptions = ["👍", "🖤", "😂", "🔥"]

    init(thread: MessageThread, service: MessageService) {
        self.thread = thread
        self.service = service
        let threadId = thread.id
        _messages = Query(
            filter: #Predicate<PersonaMessage> { $0.threadId == threadId },
            sort: [SortDescriptor(\PersonaMessage.createdAt, order: .forward)]
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            detailHeader
                .padding(.horizontal, 16)
                .padding(.top, 2)
                .padding(.bottom, 8)

            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 14) {
                        LazyVStack(spacing: 10) {
                            ForEach(messages, id: \.id) { message in
                                messageRow(for: message)
                                .id(message.id)
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 12)
                }
                .onChange(of: messages.count) {
                    if let last = messages.last {
                        withAnimation {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }

            VStack(spacing: 8) {
                if let errorMessage {
                    Text(errorMessage)
                        .font(.system(size: 12))
                        .foregroundStyle(.red)
                        .padding(.horizontal, 12)
                }

                Divider()

                TextField("Message \(displayName)...", text: $draft)
                    .submitLabel(.send)
                    .onSubmit {
                        send()
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 14)
                    .background(Color.white.opacity(0.65))
                    .clipShape(Capsule())
                .padding(.horizontal, 12)
                .padding(.top, 4)
                .padding(.bottom, 8)
            }
            .background(.ultraThinMaterial)
        }
        .background(AppTheme.messagesBackground)
        .navigationBarBackButtonHidden(true)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            try? service.markThreadRead(personaId: thread.personaId, modelContext: modelContext)
        }
    }

    private var detailHeader: some View {
        HStack(alignment: .center, spacing: 0) {
            Button {
                dismiss()
            } label: {
                AppBackIcon()
            }
            .frame(width: 44, height: 44, alignment: .leading)

            Spacer(minLength: 12)

            VStack(spacing: 2) {
                headerAvatar

                Text(displayName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.primary)

                Text("my bruh · \(presenceText)")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            Color.clear
                .frame(width: 44, height: 44)
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }

    private var matchedContact: Contact? {
        contacts.first(where: { $0.linkedPersonaId == thread.personaId })
    }

    private var displayName: String {
        matchedContact?.name ?? thread.personaId.capitalized
    }

    private var presenceText: String {
        let threshold: TimeInterval = 10 * 60
        let secondsSinceLastMessage = Date().timeIntervalSince(thread.lastMessageAt)
        return secondsSinceLastMessage <= threshold ? "online" : "offline"
    }

    private var headerAvatar: some View {
        let persona = persona(for: thread.personaId)

        return Circle()
            .fill(persona.tint.opacity(0.18))
            .frame(width: 52, height: 52)
            .overlay {
                Text(String(persona.name.prefix(1)))
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(persona.tint)
            }
    }

    private func persona(for personaId: String) -> (name: String, tint: Color) {
        if let contact = contacts.first(where: { $0.linkedPersonaId == personaId }) {
            return (contact.name, AppTheme.color(from: contact.themeColorHex, fallback: fallbackTint(for: personaId)))
        }

        return (personaId.capitalized, fallbackTint(for: personaId))
    }

    private func fallbackTint(for personaId: String) -> Color {
        switch personaId {
        case "trump":
            return .orange
        case "musk":
            return .blue
        case "zuckerberg":
            return .purple
        default:
            return .gray
        }
    }

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isSending else { return }

        draft = ""
        errorMessage = nil
        isSending = true

        Task {
            do {
                try await service.sendMessage(
                    personaId: thread.personaId,
                    text: text,
                    modelContext: modelContext,
                    userInterests: InterestPreferences.selectedInterests()
                )
            } catch {
                errorMessage = error.localizedDescription
            }
            isSending = false
        }
    }

    private func messageRow(for message: PersonaMessage) -> some View {
        let content = parseContent(from: message)
        let personaTheme = persona(for: thread.personaId).tint
        let reaction = reaction(for: message.id)

        return Group {
            if message.isIncoming {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .bottom, spacing: AppTheme.messageIncomingAvatarBubbleSpacing) {
                        incomingAvatar
                        messageContentView(
                            content: content,
                            isIncoming: true,
                            deliveryState: message.deliveryState,
                            themeColor: personaTheme
                        )
                        Spacer(minLength: 40)
                    }

                    incomingReactions(for: message.id, reaction: reaction)
                        .padding(.leading, AppTheme.messageIncomingReactionLeadingInset)
                }
            } else {
                HStack(alignment: .bottom, spacing: 8) {
                    Spacer(minLength: 40)
                    messageContentView(
                        content: content,
                        isIncoming: false,
                        deliveryState: message.deliveryState,
                        themeColor: personaTheme
                    )
                }
            }
        }
    }

    @ViewBuilder
    private func messageContentView(
        content: MessageContent,
        isIncoming: Bool,
        deliveryState: String,
        themeColor: Color
    ) -> some View {
        switch content {
        case .text(let text):
            bubble(
                text: text,
                isIncoming: isIncoming,
                deliveryState: deliveryState,
                themeColor: themeColor
            )
        case .webPreview:
            bubble(
                text: "[Web preview coming soon]",
                isIncoming: isIncoming,
                deliveryState: deliveryState,
                themeColor: themeColor
            )
        case .audio:
            bubble(
                text: "[Audio message coming soon]",
                isIncoming: isIncoming,
                deliveryState: deliveryState,
                themeColor: themeColor
            )
        }
    }

    private func parseContent(from message: PersonaMessage) -> MessageContent {
        // Extensible parser: currently all messages render as text.
        .text(message.text)
    }

    private var incomingAvatar: some View {
        let persona = persona(for: thread.personaId)

        return Circle()
            .fill(persona.tint.opacity(0.18))
            .frame(width: AppTheme.messageIncomingAvatarSize, height: AppTheme.messageIncomingAvatarSize)
            .overlay {
                Text(String(persona.name.prefix(1)))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(persona.tint)
            }
    }

    private func bubble(
        text: String,
        isIncoming: Bool,
        deliveryState: String,
        themeColor: Color
    ) -> some View {
        VStack(alignment: isIncoming ? .leading : .trailing, spacing: 4) {
            Text(text)
                .font(.system(size: 16))
                .foregroundColor(.primary)
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .background {
                    if isIncoming {
                        ZStack {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(themeColor)
                                .offset(x: -3, y: 0)

                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(AppTheme.messageBubbleBase)
                        }
                    } else {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(AppTheme.outgoingBubbleBase)
                    }
                }

            if !isIncoming && deliveryState == "failed" {
                Text("Failed to send")
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
            }
        }
    }

    @ViewBuilder
    private func incomingReactions(for messageId: String, reaction: MessageReaction) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(reaction.emoji) \(reaction.mood)")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.leading, 2)

            if let selected = selectedQuickReactions[messageId] {
                Button {
                    toggleQuickReaction(selected, for: messageId)
                } label: {
                    Text(selected)
                        .font(.system(size: 13))
                }
                .buttonStyle(.plain)
                .padding(.leading, 2)
            } else {
                HStack(spacing: 14) {
                    ForEach(quickReactionOptions, id: \.self) { emoji in
                        Button {
                            toggleQuickReaction(emoji, for: messageId)
                        } label: {
                            Text(emoji)
                                .font(.system(size: 13))
                                .opacity(0.82)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, 2)
                .padding(.leading, 2)
            }
        }
    }

    private func reaction(for messageId: String) -> MessageReaction {
        let list = MessageReaction.presets
        let stableSeed = messageId.unicodeScalars.reduce(0) { partial, scalar in
            (partial &* 31 &+ Int(scalar.value)) & 0x7fffffff
        }
        let index = stableSeed % list.count
        return list[index]
    }

    private func toggleQuickReaction(_ emoji: String, for messageId: String) {
        if selectedQuickReactions[messageId] == emoji {
            selectedQuickReactions.removeValue(forKey: messageId)
        } else {
            selectedQuickReactions[messageId] = emoji
        }
    }
}

private enum MessageContent {
    case text(String)
    case webPreview(url: URL?)
    case audio(duration: TimeInterval?)
}

private struct MessageReaction {
    let emoji: String
    let mood: String

    static let presets: [MessageReaction] = [
        .init(emoji: "😌", mood: "chill"),
        .init(emoji: "🔥", mood: "excited"),
        .init(emoji: "😎", mood: "confident"),
        .init(emoji: "🤔", mood: "curious"),
        .init(emoji: "🙂", mood: "calm"),
        .init(emoji: "🥳", mood: "hyped")
    ]
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
