import SwiftUI
import SwiftData

struct MessagesScreen: View {
    let threads: [MessageThread]
    let contacts: [Contact]
    let service: MessageService
    let onBack: () -> Void
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
            ToolbarItem(placement: .topBarLeading) {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Image(systemName: "square.and.pencil")
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
            return (contact.name, tint(for: personaId))
        }

        return (personaId.capitalized, tint(for: personaId))
    }

    private func tint(for personaId: String) -> Color {
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
    @Query private var messages: [PersonaMessage]
    @Query(sort: [SortDescriptor(\Contact.name, order: .forward)]) private var contacts: [Contact]

    let thread: MessageThread
    let service: MessageService

    @State private var draft = ""
    @State private var isSending = false
    @State private var errorMessage: String?

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
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 14) {
                        Text("Messages with \(displayName)")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .padding(.top, 8)

                        LazyVStack(spacing: 10) {
                            ForEach(messages, id: \.id) { message in
                                HStack {
                                    if message.isIncoming {
                                        bubble(text: message.text, isIncoming: true, deliveryState: message.deliveryState)
                                        Spacer(minLength: 48)
                                    } else {
                                        Spacer(minLength: 48)
                                        bubble(text: message.text, isIncoming: false, deliveryState: message.deliveryState)
                                    }
                                }
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

                HStack(alignment: .bottom, spacing: 8) {
                    Button {} label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 24))
                            .foregroundStyle(.blue)
                    }

                    HStack(alignment: .bottom, spacing: 8) {
                        Image(systemName: "camera.fill")
                            .foregroundStyle(.secondary)

                        TextField("iMessage", text: $draft, axis: .vertical)
                            .lineLimit(1...4)

                        Spacer()

                        if isSending {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Button {
                                send()
                            } label: {
                                Image(systemName: "arrow.up.circle.fill")
                                    .font(.system(size: 22))
                                    .foregroundStyle(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .gray : .blue)
                            }
                            .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                    .background(Color(.systemGray6))
                    .clipShape(Capsule())
                }
                .padding(.horizontal, 12)
                .padding(.top, 4)
                .padding(.bottom, 8)
            }
            .background(.ultraThinMaterial)
        }
        .background(Color.white)
        .navigationTitle(displayName)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            try? service.markThreadRead(personaId: thread.personaId, modelContext: modelContext)
        }
    }

    private var displayName: String {
        contacts.first(where: { $0.linkedPersonaId == thread.personaId })?.name ?? thread.personaId.capitalized
    }

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isSending else { return }

        draft = ""
        errorMessage = nil
        isSending = true

        Task {
            do {
                try await service.sendMessage(personaId: thread.personaId, text: text, modelContext: modelContext)
            } catch {
                errorMessage = error.localizedDescription
            }
            isSending = false
        }
    }

    private func bubble(text: String, isIncoming: Bool, deliveryState: String) -> some View {
        VStack(alignment: isIncoming ? .leading : .trailing, spacing: 4) {
            Text(text)
                .font(.system(size: 16))
                .foregroundColor(isIncoming ? .primary : .white)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(isIncoming ? Color(.systemGray5) : Color.blue)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

            if !isIncoming && deliveryState == "failed" {
                Text("Failed to send")
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
            }
        }
    }
}
