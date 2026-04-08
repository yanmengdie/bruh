import Foundation
import SafariServices
import SwiftUI
import SwiftData

struct MessagesScreen: View {
    let threads: [MessageThread]
    let contacts: [Contact]
    let service: MessageService
    let backgroundColor: Color
    @State private var searchText = ""

    private var filteredThreads: [MessageThread] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return threads }

        return threads.filter { thread in
            let personaName = persona(for: thread.personaId).name
            return personaName.localizedCaseInsensitiveContains(query)
                || thread.lastMessagePreview.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
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
            .padding(.top, 10)
            .padding(.bottom, 20)
        }
        .background(backgroundColor)
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always))
        .navigationTitle("")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Image(systemName: "plus")
            }
        }
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
    @StateObject private var webPreviewStore = OpenGraphPreviewStore()
    @State private var presentedSourceURL: URL?
    @State private var isPresentingSafari = false
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
        .enableUnifiedSwipeBack()
        .navigationBarBackButtonHidden(true)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $isPresentingSafari) {
            if let presentedSourceURL {
                InAppSafariView(url: presentedSourceURL)
                    .ignoresSafeArea()
            }
        }
        .task {
            try? service.markThreadRead(personaId: thread.personaId, modelContext: modelContext)
        }
    }

    private var detailHeader: some View {
        HStack(alignment: .center, spacing: 0) {
            AppBackButton {
                dismiss()
            }

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
                try await service.sendMessage(personaId: thread.personaId, text: text, modelContext: modelContext)
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
        case .webPreview(let url):
            webPreviewCard(
                url: url,
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
        if let url = firstURL(in: message.text) {
            return .webPreview(url)
        }

        return .text(message.text)
    }

    private func firstURL(in text: String) -> URL? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return nil
        }

        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = detector.firstMatch(in: text, options: [], range: range),
              let resultRange = Range(match.range, in: text) else {
            return nil
        }

        return URL(string: String(text[resultRange]))
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

    private func webPreviewCard(
        url: URL,
        isIncoming: Bool,
        deliveryState: String,
        themeColor: Color
    ) -> some View {
        let preview = webPreviewStore.preview(for: url)

        return VStack(alignment: isIncoming ? .leading : .trailing, spacing: 4) {
            ZStack {
                if isIncoming {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(themeColor)
                        .offset(x: -3, y: 0)
                }

                VStack(spacing: 0) {
                    ZStack(alignment: .topLeading) {
                        if let imageURL = preview.imageURL {
                            AsyncImage(url: imageURL) { phase in
                                switch phase {
                                case .success(let image):
                                    image
                                        .resizable()
                                        .scaledToFill()
                                default:
                                    heroFallback()
                                }
                            }
                        } else {
                            heroFallback()
                        }

                        Text(preview.source)
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.black.opacity(0.35))
                            .clipShape(Capsule())
                            .padding(.top, 12)
                            .padding(.leading, 12)

                        Text(preview.heroText)
                            .font(.system(size: 42, weight: .black, design: .rounded))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    }
                    .frame(height: 150)
                    .clipped()

                    VStack(alignment: .leading, spacing: 10) {
                        Text(preview.headline)
                            .font(.system(size: 19, weight: .semibold))
                            .foregroundStyle(.primary)
                            .lineSpacing(1.8)

                        Text(preview.summary)
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 14)
                    .background(AppTheme.messageBubbleBase)
                }
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .frame(maxWidth: 540, alignment: isIncoming ? .leading : .trailing)
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .onTapGesture {
                presentedSourceURL = preview.link
                isPresentingSafari = true
            }
            .task(id: url.absoluteString) {
                await webPreviewStore.load(url: url)
            }

            if !isIncoming && deliveryState == "failed" {
                Text("Failed to send")
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
            }
        }
    }

    private func heroFallback() -> some View {
        LinearGradient(
            colors: [Color(red: 0.83, green: 0.08, blue: 0.16), Color(red: 0.71, green: 0.00, blue: 0.05)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
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
    case webPreview(URL)
    case audio(duration: TimeInterval?)
}

private struct WebPreviewCardData {
    let source: String
    let heroText: String
    let headline: String
    let summary: String
    let imageURL: URL?
    let link: URL

    static func fallback(for url: URL) -> WebPreviewCardData {
        let host = url.host?.replacingOccurrences(of: "www.", with: "") ?? "LINK"
        let source = host.components(separatedBy: ".").first?.uppercased() ?? "LINK"

        return WebPreviewCardData(
            source: source,
            heroText: source,
            headline: url.absoluteString,
            summary: "Link preview",
            imageURL: nil,
            link: url
        )
    }
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

private struct InAppSafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let controller = SFSafariViewController(url: url)
        controller.dismissButtonStyle = .close
        return controller
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}

@MainActor
private final class OpenGraphPreviewStore: ObservableObject {
    @Published private var cache: [String: WebPreviewCardData] = [:]
    private var inFlight: Set<String> = []

    func preview(for url: URL) -> WebPreviewCardData {
        cache[url.absoluteString] ?? .fallback(for: url)
    }

    func load(url: URL) async {
        let key = url.absoluteString
        if cache[key] != nil || inFlight.contains(key) { return }
        inFlight.insert(key)
        defer { inFlight.remove(key) }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                return
            }

            guard let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
                return
            }

            if let parsed = OpenGraphParser.parse(html: html, pageURL: url) {
                cache[key] = parsed
            }
        } catch {
            return
        }
    }
}

private enum OpenGraphParser {
    static func parse(html: String, pageURL: URL) -> WebPreviewCardData? {
        let title = firstMetaContent(html: html, keys: ["og:title", "twitter:title"]) ?? pageTitle(html: html)
        let description = firstMetaContent(html: html, keys: ["og:description", "twitter:description", "description"])
        let imageString = firstMetaContent(html: html, keys: ["og:image", "twitter:image"])
        let siteName = firstMetaContent(html: html, keys: ["og:site_name"]) ?? domainLabel(from: pageURL)

        guard title != nil || description != nil || imageString != nil else { return nil }

        let imageURL = resolveURL(imageString, relativeTo: pageURL)
        let headline = decoded(title ?? pageURL.absoluteString)
        let summary = decoded(description ?? "Open link for details")
        let source = decoded(siteName.uppercased())

        return WebPreviewCardData(
            source: source,
            heroText: heroText(from: source),
            headline: headline,
            summary: summary,
            imageURL: imageURL,
            link: pageURL
        )
    }

    static func firstMetaContent(html: String, keys: [String]) -> String? {
        for key in keys {
            if let value = firstMetaContent(html: html, key: key), !value.isEmpty {
                return value
            }
        }
        return nil
    }

    static func firstMetaContent(html: String, key: String) -> String? {
        let patterns = [
            "<meta[^>]*?(?:property|name)\\s*=\\s*[\"']\(NSRegularExpression.escapedPattern(for: key))[\"'][^>]*?content\\s*=\\s*[\"']([^\"']+)[\"'][^>]*?>",
            "<meta[^>]*?content\\s*=\\s*[\"']([^\"']+)[\"'][^>]*?(?:property|name)\\s*=\\s*[\"']\(NSRegularExpression.escapedPattern(for: key))[\"'][^>]*?>"
        ]

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
                continue
            }
            let range = NSRange(html.startIndex..<html.endIndex, in: html)
            if let match = regex.firstMatch(in: html, options: [], range: range),
               match.numberOfRanges > 1,
               let capture = Range(match.range(at: 1), in: html) {
                return String(html[capture]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        return nil
    }

    static func pageTitle(html: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: "<title[^>]*>(.*?)</title>", options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return nil
        }
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        guard let match = regex.firstMatch(in: html, options: [], range: range),
              match.numberOfRanges > 1,
              let capture = Range(match.range(at: 1), in: html) else {
            return nil
        }

        return String(html[capture]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func resolveURL(_ raw: String?, relativeTo baseURL: URL) -> URL? {
        guard let raw, !raw.isEmpty else { return nil }
        if let absolute = URL(string: raw), absolute.scheme != nil {
            return absolute
        }
        return URL(string: raw, relativeTo: baseURL)?.absoluteURL
    }

    static func domainLabel(from url: URL) -> String {
        let host = url.host?.replacingOccurrences(of: "www.", with: "") ?? "LINK"
        return host.components(separatedBy: ".").first?.uppercased() ?? "LINK"
    }

    static func heroText(from source: String) -> String {
        let cleaned = source.replacingOccurrences(of: " ", with: "")
        return String(cleaned.prefix(10))
    }

    static func decoded(_ value: String) -> String {
        var decoded = value
        let entities: [String: String] = [
            "&amp;": "&",
            "&quot;": "\"",
            "&#39;": "'",
            "&lt;": "<",
            "&gt;": ">"
        ]
        for (entity, replacement) in entities {
            decoded = decoded.replacingOccurrences(of: entity, with: replacement)
        }
        return decoded
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
