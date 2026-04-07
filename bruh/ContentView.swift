import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\MessageThread.lastMessageAt, order: .reverse)]) private var threads: [MessageThread]

    @State private var currentDestination: AppDestination? = nil
    @State private var messageService = MessageService()

    var body: some View {
        ZStack {
            if let destination = currentDestination {
                destinationView(for: destination)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(.move(edge: .trailing))
            } else {
                HomeScreen(onNavigate: { destination in
                    withAnimation(.easeInOut(duration: 0.25)) {
                        currentDestination = destination
                    }
                })
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.easeInOut(duration: 0.25), value: currentDestination)
        .task {
            try? messageService.ensureThreadsExist(modelContext: modelContext)
        }
    }

    @ViewBuilder
    private func destinationView(for destination: AppDestination) -> some View {
        switch destination {
        case .feed:
            NavigationStack {
                FeedView()
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            backButton
                        }
                    }
            }

        case .imessage:
            NavigationStack {
                ScrollView {
                    VStack(spacing: 14) {
                        messageSearchBar
                            .padding(.horizontal, 16)

                        VStack(spacing: 0) {
                            ForEach(Array(threads.enumerated()), id: \.element.id) { index, thread in
                                NavigationLink {
                                    MessageDetailView(thread: thread, service: messageService)
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
                .background(Color(red: 0.95, green: 0.96, blue: 0.98))
                .navigationTitle("Messages")
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        backButton
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Image(systemName: "square.and.pencil")
                    }
                }
            }

        case .settings:
            NavigationStack {
                List {
                    Label("通知设置", systemImage: "bell.badge")
                    Label("内容偏好", systemImage: "slider.horizontal.3")
                    Label("关于 Bruh", systemImage: "info.circle")
                }
                .navigationTitle("设置")
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        backButton
                    }
                }
            }
        }
    }

    private var backButton: some View {
        Button {
            withAnimation {
                currentDestination = nil
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "chevron.left")
                Text("桌面")
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
        switch personaId {
        case "trump":
            return ("Donald Trump", .orange)
        case "musk":
            return ("Elon Musk", .blue)
        case "zuckerberg":
            return ("Mark Zuckerberg", .purple)
        default:
            return (personaId.capitalized, .gray)
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
        switch thread.personaId {
        case "trump": return "Donald Trump"
        case "musk": return "Elon Musk"
        case "zuckerberg": return "Mark Zuckerberg"
        default: return thread.personaId.capitalized
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

#Preview {
    ContentView()
        .modelContainer(
            for: [
                Persona.self,
                PersonaPost.self,
                SourceItem.self,
                MessageThread.self,
                PersonaMessage.self,
                FeedComment.self,
                FeedLike.self,
            ],
            inMemory: true
        )
}
