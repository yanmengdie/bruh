import Foundation
import AVFoundation
import AVKit
import SafariServices
import SwiftUI
import SwiftData
import UIKit

struct MessagesScreen: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\ContentDelivery.sortDate, order: .reverse)]) private var deliveries: [ContentDelivery]
    @Query(sort: [SortDescriptor(\PersonaMessage.createdAt, order: .reverse)]) private var recentMessages: [PersonaMessage]
    let threads: [MessageThread]
    let contacts: [Contact]
    let service: MessageService
    let backgroundColor: Color
    @State private var searchText = ""
    @State private var hasRequestedStarterRefresh = false

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
            let personaName = persona(for: thread.personaId).name
            return personaName.localizedCaseInsensitiveContains(query)
                || latestPreview(for: thread).localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        ZStack {
            backgroundColor.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 14) {
                    if !filteredThreads.isEmpty {
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
        .navigationTitle("")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Image(systemName: "plus")
            }
        }
        .task {
            await refreshStartersIfNeeded()
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
            avatarCircle(for: thread.personaId, size: 50)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(persona.name)
                        .font(.system(size: 16, weight: unreadCount(for: thread) > 0 ? .semibold : .regular))
                        .foregroundStyle(.primary)
                    Spacer()
                    Text(relativeTime(latestActivityDate(for: thread)))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Text(latestPreview(for: thread))
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Spacer()

                    if unreadCount(for: thread) > 0 {
                        Text("\(unreadCount(for: thread))")
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

    private func avatarCircle(for personaId: String, size: CGFloat) -> some View {
        let persona = persona(for: personaId)
        let avatarName = contacts.first(where: { $0.linkedPersonaId == personaId })?.avatarName ?? ""

        return Circle()
            .fill(persona.tint.opacity(0.18))
            .frame(width: size, height: size)
            .overlay {
                if !avatarName.isEmpty, UIImage(named: avatarName) != nil {
                    Image(avatarName)
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

    private func fallbackTint(for personaId: String) -> Color {
        switch personaId {
        case "trump":
            return .orange
        case "musk":
            return .blue
        case "zuckerberg":
            return .purple
        case "justin_sun":
            return Color(red: 0.11, green: 0.74, blue: 0.63)
        default:
            return .gray
        }
    }

    private func relativeTime(_ date: Date) -> String {
        guard date > Date.distantPast else { return "刚刚" }

        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private var acceptedPersonaIds: Set<String> {
        Set(
            contacts
                .filter { $0.relationshipStatusValue == .accepted }
                .compactMap(\.linkedPersonaId)
        )
    }

    private var messageDeliveries: [ContentDelivery] {
        deliveries.filter { delivery in
            delivery.channelValue == .message
                && delivery.isVisible
                && acceptedPersonaIds.contains(delivery.personaId ?? "")
        }
    }

    private func latestMessageDelivery(for personaId: String) -> ContentDelivery? {
        messageDeliveries.first(where: { $0.personaId == personaId })
    }

    private func latestPersistedMessage(for personaId: String) -> PersonaMessage? {
        recentMessages.first(where: { $0.threadId == personaId })
    }

    private func latestPreview(for thread: MessageThread) -> String {
        if let message = latestPersistedMessage(for: thread.personaId) {
            let preview = messagePreview(for: message)
            if !preview.isEmpty {
                return preview
            }
        }

        let preview = thread.lastMessagePreview.trimmingCharacters(in: .whitespacesAndNewlines)
        if !preview.isEmpty {
            return preview
        }
        if let preview = latestMessageDelivery(for: thread.personaId)?.previewText,
           !preview.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return preview
        }
        return "开始聊天"
    }

    private func latestActivityDate(for thread: MessageThread) -> Date {
        let latestMessageDate = latestPersistedMessage(for: thread.personaId)?.createdAt ?? .distantPast
        let latestDeliveryDate = latestMessageDelivery(for: thread.personaId)?.sortDate ?? .distantPast
        return max(thread.lastMessageAt, max(latestMessageDate, latestDeliveryDate))
    }

    private func unreadCount(for thread: MessageThread) -> Int {
        MessageReadStateStore.unreadCount(
            for: thread.personaId,
            deliveries: messageDeliveries,
            fallbackCount: thread.unreadCount
        )
    }

    private func messagePreview(for message: PersonaMessage) -> String {
        if message.audioOnly,
           let audioUrl = message.audioUrl?.trimmingCharacters(in: .whitespacesAndNewlines),
           !audioUrl.isEmpty {
            return "[Voice]"
        }

        let trimmed = message.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard message.imageUrl != nil else { return trimmed }
        return trimmed.isEmpty ? "[图片]" : "[图片] \(trimmed)"
    }

    private func refreshStartersIfNeeded() async {
        guard !hasRequestedStarterRefresh else { return }
        guard !acceptedPersonaIds.isEmpty else { return }
        hasRequestedStarterRefresh = true
        await service.refreshStarterMessages(
            modelContext: modelContext,
            userInterests: CurrentUserProfileStore.selectedInterests(in: modelContext)
        )
    }
}

private struct MessageDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var messages: [PersonaMessage]
    @Query(sort: [SortDescriptor(\Contact.name, order: .forward)]) private var contacts: [Contact]

    let thread: MessageThread
    let service: MessageService
    private let timestampProvider: any MessageTimestampProviding

    @State private var draft = ""
    @State private var isSending = false
    @State private var errorMessage: String?
    @State private var selectedQuickReactions: [String: String] = [:]
    @StateObject private var webPreviewStore = OpenGraphPreviewStore()
    @StateObject private var audioPlayback = MessageAudioPlaybackController()
    @State private var presentedSourceURL: URL?
    @State private var isPresentingSafari = false
    @State private var effectPlayer: AVPlayer?
    @State private var isShowingExcitedEffect = false
    @State private var hasCheckedEntryEffect = false
    @State private var entryUnreadCount = 0
    private let quickReactionOptions = ["👍", "🖤", "😂", "🔥"]
    private let isExcitedEntryEffectEnabled = false

    init(
        thread: MessageThread,
        service: MessageService,
        timestampProvider: any MessageTimestampProviding = RealTimeMessageTimestampProvider()
    ) {
        self.thread = thread
        self.service = service
        self.timestampProvider = timestampProvider
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
                            ForEach(Array(messages.enumerated()), id: \.element.id) { index, message in
                                if let timestamp = timestampProvider.timestampLabel(
                                    for: message,
                                    previous: index > 0 ? messages[index - 1] : nil
                                ) {
                                    messageTimestamp(timestamp)
                                }

                                messageRow(for: message)
                                .id(message.id)
                            }

                            if isSending {
                                waitingMessageRow
                                    .id("pending-reply-indicator")
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
                .onChange(of: isSending) { _, sending in
                    guard sending else { return }
                    withAnimation {
                        proxy.scrollTo("pending-reply-indicator", anchor: .bottom)
                    }
                }
            }

            VStack(spacing: 8) {
                if let inlineErrorMessage {
                    Text(inlineErrorMessage)
                        .font(.system(size: 12))
                        .foregroundStyle(.red)
                        .padding(.horizontal, 12)
                }

                Divider()

                HStack(spacing: 10) {
                    Button {
                        send(requestImage: true)
                    } label: {
                        Image(systemName: "photo.badge.plus")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 42, height: 42)
                            .background(Color.white.opacity(0.65))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .disabled(isSending || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    TextField("Message \(displayName)...", text: $draft)
                        .submitLabel(.send)
                        .onSubmit {
                            send()
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 14)
                        .background(Color.white.opacity(0.65))
                        .clipShape(Capsule())

                    Button {
                        send()
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 28))
                            .foregroundColor(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .secondary : .blue)
                    }
                    .buttonStyle(.plain)
                    .disabled(isSending || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
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
        .overlay {
            if isShowingExcitedEffect, let effectPlayer {
                ZStack {
                    Color.black.opacity(0.12)
                        .ignoresSafeArea()

                    EffectVideoView(player: effectPlayer)
                        .frame(width: 240, height: 240)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .shadow(color: .black.opacity(0.18), radius: 12, y: 6)
                }
                .transition(.opacity)
            }
        }
        .task {
            entryUnreadCount = currentUnreadCount
            try? service.markThreadRead(personaId: thread.personaId, modelContext: modelContext)
        }
        .task(id: messages.count) {
            maybePlayEntryExcitedEffect()
        }
        .onReceive(NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime)) { note in
            guard let endedItem = note.object as? AVPlayerItem else {
                return
            }

            if let currentItem = effectPlayer?.currentItem, endedItem == currentItem {
                isShowingExcitedEffect = false
                effectPlayer?.pause()
                effectPlayer = nil
                return
            }
        }
        .onDisappear {
            effectPlayer?.pause()
            effectPlayer = nil
            isShowingExcitedEffect = false
            cleanupAudioPlayer()
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
        let secondsSinceLastMessage = Date().timeIntervalSince(latestConversationDate)
        return secondsSinceLastMessage <= threshold ? "online" : "offline"
    }

    private var latestConversationDate: Date {
        messages.last?.createdAt ?? thread.lastMessageAt
    }

    private var currentUnreadCount: Int {
        let incomingMessages = messages.filter(\.isIncoming)
        guard !incomingMessages.isEmpty else { return max(0, thread.unreadCount) }

        let cutoff = MessageReadStateStore.lastReadAt(for: thread.personaId) ?? .distantPast
        return incomingMessages.reduce(0) { count, message in
            count + (message.createdAt > cutoff ? 1 : 0)
        }
    }

    private var headerAvatar: some View {
        avatarCircle(size: 52)
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
        case "justin_sun":
            return Color(red: 0.11, green: 0.74, blue: 0.63)
        default:
            return .gray
        }
    }

    private func avatarCircle(size: CGFloat) -> some View {
        let persona = persona(for: thread.personaId)
        let avatarName = matchedContact?.avatarName ?? ""

        return Circle()
            .fill(persona.tint.opacity(0.18))
            .frame(width: size, height: size)
            .overlay {
                if !avatarName.isEmpty, UIImage(named: avatarName) != nil {
                    Image(avatarName)
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

    private func send(requestImage: Bool = false) {
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
                    userInterests: CurrentUserProfileStore.selectedInterests(in: modelContext),
                    requestImage: requestImage
                )
            } catch {
                errorMessage = error.localizedDescription
            }
            isSending = false
        }
    }

    private var waitingMessageRow: some View {
        HStack(alignment: .bottom, spacing: AppTheme.messageIncomingAvatarBubbleSpacing) {
            incomingAvatar
            TypingIndicatorBubble(themeColor: persona(for: thread.personaId).tint)
            Spacer(minLength: 40)
        }
    }

    private var inlineErrorMessage: String? {
        if let errorMessage, !errorMessage.isEmpty {
            return errorMessage
        }
        return audioPlayback.lastErrorMessage
    }

    private func resolvedVoiceLabel(for message: PersonaMessage) -> String {
        let trimmed = message.voiceLabel?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmed.isEmpty {
            return trimmed
        }

        let name = persona(for: message.personaId).name
        return name.hasSuffix("s") ? "\(name)' voice" : "\(name)'s voice"
    }

    private func resolveAudioDurationIfNeeded(
        for messageId: String,
        from url: URL,
        existingDuration: TimeInterval?
    ) async {
        await audioPlayback.resolveDurationIfNeeded(
            for: messageId,
            from: url,
            existingDuration: existingDuration
        )
    }

    private func cleanupAudioPlayer(resetState: Bool = true) {
        audioPlayback.cleanup(resetState: resetState)
    }

    private func toggleAudioPlayback(for messageId: String, url: URL) {
        errorMessage = nil
        audioPlayback.togglePlayback(for: messageId, url: url)
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

    private func messageTimestamp(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Color.black.opacity(0.30))
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, 2)
            .padding(.bottom, 4)
    }

    @ViewBuilder
    private func messageContentView(
        content: MessageContent,
        isIncoming: Bool,
        deliveryState: String,
        themeColor: Color
    ) -> some View {
        switch content {
        case .text(let text, let imageUrl):
            bubble(
                text: text,
                imageURL: imageUrl,
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
        case .audio(let url, let duration, let label, let messageId):
            voiceMessageCard(
                url: url,
                duration: duration,
                label: label,
                messageId: messageId,
                isIncoming: isIncoming,
                deliveryState: deliveryState,
                themeColor: themeColor
            )
        }
    }

    private func parseContent(from message: PersonaMessage) -> MessageContent {
        if message.audioOnly,
           let audioUrl = message.audioUrl.flatMap(URL.init(string:)) {
            let resolvedDuration = audioPlayback.resolvedDurations[message.id] ?? message.audioDuration
            return .audio(
                audioUrl,
                duration: resolvedDuration,
                label: resolvedVoiceLabel(for: message),
                messageId: message.id
            )
        }

        if let imageUrl = message.imageUrl.flatMap(URL.init(string:)) {
            return .text(message.text, imageUrl: imageUrl)
        }

        if let url = firstURL(in: message.text) {
            return .webPreview(url)
        }

        return .text(message.text, imageUrl: nil)
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
        avatarCircle(size: AppTheme.messageIncomingAvatarSize)
    }

    private func bubble(
        text: String,
        imageURL: URL?,
        isIncoming: Bool,
        deliveryState: String,
        themeColor: Color
    ) -> some View {
        VStack(alignment: isIncoming ? .leading : .trailing, spacing: 4) {
            VStack(alignment: .leading, spacing: imageURL == nil ? 0 : 10) {
                if !text.isEmpty {
                    Text(text)
                        .font(.system(size: 16))
                        .foregroundColor(.primary)
                }

                if let imageURL {
                    AsyncImage(url: imageURL) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                                .frame(width: 220, height: 220)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        case .failure:
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.black.opacity(0.06))
                                .frame(width: 220, height: 220)
                                .overlay {
                                    Image(systemName: "photo")
                                        .font(.system(size: 28))
                                        .foregroundStyle(.secondary)
                                }
                        case .empty:
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.black.opacity(0.04))
                                .frame(width: 220, height: 220)
                                .overlay {
                                    ProgressView()
                                }
                        @unknown default:
                            EmptyView()
                        }
                    }
                }
            }
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

    private func voiceMessageCard(
        url: URL,
        duration: TimeInterval?,
        label: String,
        messageId: String,
        isIncoming: Bool,
        deliveryState: String,
        themeColor: Color
    ) -> some View {
        let effectiveDuration = audioPlayback.resolvedDurations[messageId] ?? duration
        let isActive = audioPlayback.activeMessageId == messageId
        let progress = isActive ? audioPlayback.progress : 0
        let isLoading = audioPlayback.loadingMessageId == messageId

        return VStack(alignment: isIncoming ? .leading : .trailing, spacing: 4) {
            Button {
                toggleAudioPlayback(for: messageId, url: url)
            } label: {
                VoiceMessageBubbleView(
                    themeColor: themeColor,
                    isPlaying: isActive && audioPlayback.isPlaying,
                    isLoading: isLoading,
                    progress: progress,
                    duration: effectiveDuration,
                    label: label
                )
            }
            .buttonStyle(.plain)
            .task(id: messageId) {
                await resolveAudioDurationIfNeeded(
                    for: messageId,
                    from: url,
                    existingDuration: effectiveDuration
                )
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
            HStack(spacing: 4) {
                reactionEmojiText(reaction.emoji)
                Text(reaction.mood)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .padding(.leading, 2)

            if let selected = selectedQuickReactions[messageId] {
                Button {
                    toggleQuickReaction(selected, for: messageId)
                } label: {
                    reactionEmojiText(selected)
                }
                .buttonStyle(.plain)
                .padding(.leading, 2)
            } else {
                HStack(spacing: 14) {
                    ForEach(quickReactionOptions, id: \.self) { emoji in
                        Button {
                            toggleQuickReaction(emoji, for: messageId)
                        } label: {
                            reactionEmojiText(emoji)
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
        if let forcedId = forcedExcitedMessageIdForTesting, forcedId == messageId {
            return MessageReaction.presets.first(where: { $0.mood == "excited" }) ?? .init(emoji: "🔥", mood: "excited")
        }

        let list = MessageReaction.presets
        let stableSeed = messageId.unicodeScalars.reduce(0) { partial, scalar in
            (partial &* 31 &+ Int(scalar.value)) & 0x7fffffff
        }
        let index = stableSeed % list.count
        return list[index]
    }

    private var forcedExcitedMessageIdForTesting: String? {
        guard thread.personaId == "trump" else { return nil }
        return messages.last(where: { $0.isIncoming })?.id
    }

    private func maybePlayEntryExcitedEffect() {
        guard isExcitedEntryEffectEnabled else { return }
        guard !hasCheckedEntryEffect else { return }
        guard !messages.isEmpty else { return }
        hasCheckedEntryEffect = true

        guard entryUnreadCount > 0 else { return }
        guard let latestIncoming = messages.last(where: { $0.isIncoming }) else { return }
        guard reaction(for: latestIncoming.id).mood == "excited" else { return }
        guard let videoURL = Bundle.main.url(forResource: "trump_joy", withExtension: "mp4") else { return }

        let player = AVPlayer(url: videoURL)
        effectPlayer = player
        isShowingExcitedEffect = true
        player.play()
    }

    private func toggleQuickReaction(_ emoji: String, for messageId: String) {
        if selectedQuickReactions[messageId] == emoji {
            selectedQuickReactions.removeValue(forKey: messageId)
        } else {
            selectedQuickReactions[messageId] = emoji
        }
    }

    private func reactionEmojiText(_ emoji: String) -> some View {
        Text(verbatim: emoji)
            .font(.system(size: 15))
    }
}

private enum MessageContent {
    case text(String, imageUrl: URL?)
    case webPreview(URL)
    case audio(URL, duration: TimeInterval?, label: String, messageId: String)
}

private struct TypingIndicatorBubble: View {
    let themeColor: Color

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.34)) { context in
            let phase = Int(context.date.timeIntervalSinceReferenceDate / 0.34) % 3

            HStack(spacing: 7) {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .fill(Color.black.opacity(phase == index ? 0.34 : 0.16))
                        .frame(width: 8, height: 8)
                        .scaleEffect(phase == index ? 1.08 : 0.92)
                        .animation(.easeInOut(duration: 0.22), value: phase)
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(themeColor)
                    .offset(x: -3, y: 0)

                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(AppTheme.messageBubbleBase)
            }
        }
    }
}

private struct VoiceMessageBubbleView: View {
    let themeColor: Color
    let isPlaying: Bool
    let isLoading: Bool
    let progress: Double
    let duration: TimeInterval?
    let label: String

    private let waveformHeights: [CGFloat] = [10, 15, 21, 13, 19, 25, 15, 11, 18, 24, 16, 12, 20, 27, 17, 12, 18]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(themeColor.opacity(0.18))
                        .frame(width: 42, height: 42)

                    if isLoading {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(themeColor)
                            .scaleEffect(0.75)
                    } else {
                        Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(themeColor)
                            .offset(x: isPlaying ? 0 : 1)
                    }
                }

                HStack(alignment: .center, spacing: 4) {
                    ForEach(Array(waveformHeights.enumerated()), id: \.offset) { index, height in
                        Capsule()
                            .fill(barColor(for: index))
                            .frame(width: 4, height: height)
                    }
                }

                Text(durationText)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color.black.opacity(0.42))
                    .monospacedDigit()
            }

            HStack(spacing: 4) {
                Image(systemName: "waveform")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(themeColor.opacity(0.82))

                Text("voice · \(label)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.94))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(themeColor.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: themeColor.opacity(0.08), radius: 8, y: 4)
    }

    private func barColor(for index: Int) -> Color {
        let activeBars = max(Int(round(progress * Double(waveformHeights.count))), isPlaying || isLoading ? 1 : 6)
        if index < activeBars {
            return themeColor.opacity(isPlaying ? 0.92 : (isLoading ? 0.74 : 0.62))
        }
        return Color.black.opacity(0.14)
    }

    private var durationText: String {
        guard let duration, duration > 0, duration.isFinite else { return "0:00" }
        let totalSeconds = Int(duration.rounded())
        return String(format: "%d:%02d", totalSeconds / 60, totalSeconds % 60)
    }
}

@MainActor
private final class MessageAudioPlaybackController: NSObject, ObservableObject, @preconcurrency AVAudioPlayerDelegate {
    @Published private(set) var activeMessageId: String?
    @Published private(set) var progress = 0.0
    @Published private(set) var isPlaying = false
    @Published private(set) var loadingMessageId: String?
    @Published private(set) var lastErrorMessage: String?
    @Published private(set) var resolvedDurations: [String: TimeInterval] = [:]

    private var player: AVAudioPlayer?
    private var prepareTask: Task<Void, Never>?
    private var progressTimer: Timer?

    func resolveDurationIfNeeded(
        for messageId: String,
        from url: URL,
        existingDuration: TimeInterval?
    ) async {
        if let existingDuration, existingDuration > 0 {
            resolvedDurations[messageId] = existingDuration
            return
        }

        if let cachedDuration = resolvedDurations[messageId], cachedDuration > 0 {
            return
        }

        do {
            let payload = try await playbackPayload(for: messageId, remoteURL: url)
            let duration = try playableDuration(from: payload)
            guard duration.isFinite, duration > 0 else { return }
            resolvedDurations[messageId] = duration
        } catch {
            return
        }
    }

    func togglePlayback(for messageId: String, url: URL) {
        if loadingMessageId == messageId {
            prepareTask?.cancel()
            cleanup()
            return
        }

        if activeMessageId == messageId, let player {
            if isPlaying {
                player.pause()
                stopProgressTimer()
                isPlaying = false
            } else {
                if player.play() {
                    startProgressTimer()
                    isPlaying = true
                } else {
                    failPlayback("Voice playback failed to start.")
                }
            }
            return
        }

        cleanup(resetState: false)
        activeMessageId = messageId
        loadingMessageId = messageId
        progress = 0
        isPlaying = false
        lastErrorMessage = nil

        prepareTask = Task { [weak self] in
            guard let self else { return }

            do {
                try configureAudioSession()
                print("[Voice] Preparing playback for \(messageId)")
                let player = try await preparePlayer(for: messageId, remoteURL: url)
                guard !Task.isCancelled else { return }

                self.player = player
                self.loadingMessageId = nil
                self.resolvedDurations[messageId] = player.duration

                if player.play() {
                    print("[Voice] Started playback for \(messageId) (\(player.duration)s)")
                    self.isPlaying = true
                    self.startProgressTimer()
                } else {
                    self.failPlayback("Voice playback failed to start.")
                }
            } catch {
                guard !Task.isCancelled else { return }
                print("[Voice] Playback failed for \(messageId): \(error.localizedDescription)")
                self.failPlayback(userFacingErrorMessage(for: error))
            }
        }
    }

    func cleanup(resetState: Bool = true) {
        prepareTask?.cancel()
        prepareTask = nil

        stopProgressTimer()
        player?.pause()
        player = nil

        if resetState {
            activeMessageId = nil
            progress = 0
            isPlaying = false
            loadingMessageId = nil
            lastErrorMessage = nil
        } else {
            isPlaying = false
            loadingMessageId = nil
        }
    }

    deinit {
        prepareTask?.cancel()
    }

    private func configureAudioSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default, options: [])
        try session.setActive(true)
    }

    private func preparePlayer(for messageId: String, remoteURL: URL) async throws -> AVAudioPlayer {
        do {
            let payload = try await playbackPayload(for: messageId, remoteURL: remoteURL)
            return try makePlayer(from: payload)
        } catch {
            print("[Voice] Retrying fresh download for \(messageId)")
            let payload = try await playbackPayload(for: messageId, remoteURL: remoteURL, forceRedownload: true)
            return try makePlayer(from: payload)
        }
    }

    private func makePlayer(from payload: CachedVoicePayload) throws -> AVAudioPlayer {
        let player = try AVAudioPlayer(data: payload.data, fileTypeHint: payload.fileTypeHint)
        player.delegate = self
        player.volume = 1
        player.prepareToPlay()

        guard player.duration.isFinite, player.duration > 0.05 else {
            throw VoicePlaybackError.invalidAudioData
        }

        return player
    }

    private func playableDuration(from payload: CachedVoicePayload) throws -> TimeInterval {
        let player = try AVAudioPlayer(data: payload.data, fileTypeHint: payload.fileTypeHint)
        let duration = player.duration
        guard duration.isFinite, duration > 0.05 else {
            throw VoicePlaybackError.invalidAudioData
        }
        return duration
    }

    private func playbackPayload(
        for messageId: String,
        remoteURL: URL,
        forceRedownload: Bool = false
    ) async throws -> CachedVoicePayload {
        let cacheDirectory = try voiceCacheDirectory()
        let fileExtension = remoteURL.pathExtension.isEmpty ? "wav" : remoteURL.pathExtension.lowercased()
        let localURL = cacheDirectory.appendingPathComponent("\(messageId).\(fileExtension)")
        let fileManager = FileManager.default

        if forceRedownload, fileManager.fileExists(atPath: localURL.path) {
            try? fileManager.removeItem(at: localURL)
        }

        if !forceRedownload,
           fileManager.fileExists(atPath: localURL.path) {
            let cachedData = try Data(contentsOf: localURL)
            let cachedPayload = CachedVoicePayload(
                data: cachedData,
                fileTypeHint: audioFileTypeHint(mimeType: nil, remoteURL: remoteURL, data: cachedData),
                localURL: localURL
            )

            if isLikelyPlayableAudio(cachedPayload.data, mimeType: nil) {
                return cachedPayload
            }

            try? fileManager.removeItem(at: localURL)
        }

        var request = URLRequest(url: remoteURL)
        request.timeoutInterval = 30
        request.setValue("audio/*", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw VoicePlaybackError.invalidResponse
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            throw VoicePlaybackError.httpStatus(httpResponse.statusCode)
        }

        let mimeType = httpResponse.mimeType?.lowercased()
        guard isLikelyPlayableAudio(data, mimeType: mimeType) else {
            throw VoicePlaybackError.invalidAudioData
        }

        try data.write(to: localURL, options: .atomic)
        return CachedVoicePayload(
            data: data,
            fileTypeHint: audioFileTypeHint(mimeType: mimeType, remoteURL: remoteURL, data: data),
            localURL: localURL
        )
    }

    private func voiceCacheDirectory() throws -> URL {
        let baseDirectory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let directory = baseDirectory.appendingPathComponent("VoiceMessages", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func startProgressTimer() {
        stopProgressTimer()

        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let player = self.player else { return }
                let duration = player.duration
                guard duration.isFinite, duration > 0 else { return }
                self.progress = min(max(player.currentTime / duration, 0), 1)
            }
        }
    }

    private func stopProgressTimer() {
        progressTimer?.invalidate()
        progressTimer = nil
    }

    private func failPlayback(_ message: String) {
        cleanup(resetState: false)
        lastErrorMessage = message
    }

    private func userFacingErrorMessage(for error: Error) -> String {
        if let voiceError = error as? VoicePlaybackError {
            return voiceError.message
        }
        return "Voice playback failed. Try tapping again."
    }

    private func isLikelyPlayableAudio(_ data: Data, mimeType: String?) -> Bool {
        guard data.count > 256 else { return false }

        if let mimeType, mimeType.hasPrefix("audio/") {
            return true
        }

        if data.starts(with: [0x52, 0x49, 0x46, 0x46]), data.count > 12 {
            let waveHeader = Data([0x57, 0x41, 0x56, 0x45])
            return data.subdata(in: 8..<12) == waveHeader
        }

        if data.starts(with: [0x49, 0x44, 0x33]) {
            return true
        }

        if let firstByte = data.first, firstByte == 0xFF {
            return true
        }

        return false
    }

    private func audioFileTypeHint(mimeType: String?, remoteURL: URL, data: Data) -> String? {
        if let mimeType {
            switch mimeType {
            case "audio/wav", "audio/wave", "audio/x-wav":
                return AVFileType.wav.rawValue
            case "audio/mpeg", "audio/mp3":
                return AVFileType.mp3.rawValue
            case "audio/mp4", "audio/x-m4a", "audio/m4a":
                return AVFileType.m4a.rawValue
            default:
                break
            }
        }

        let fileExtension = remoteURL.pathExtension.lowercased()
        switch fileExtension {
        case "wav":
            return AVFileType.wav.rawValue
        case "mp3":
            return AVFileType.mp3.rawValue
        case "m4a", "mp4":
            return AVFileType.m4a.rawValue
        default:
            break
        }

        if data.starts(with: [0x52, 0x49, 0x46, 0x46]), data.count > 12 {
            return AVFileType.wav.rawValue
        }
        if data.starts(with: [0x49, 0x44, 0x33]) || data.first == 0xFF {
            return AVFileType.mp3.rawValue
        }

        return nil
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        stopProgressTimer()
        self.player = nil
        progress = 0
        isPlaying = false
        loadingMessageId = nil
    }

    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        failPlayback(error?.localizedDescription ?? "Voice playback failed to decode.")
    }
}

private struct CachedVoicePayload {
    let data: Data
    let fileTypeHint: String?
    let localURL: URL
}

private enum VoicePlaybackError: Error {
    case invalidResponse
    case httpStatus(Int)
    case invalidAudioData

    var message: String {
        switch self {
        case .invalidResponse:
            return "Voice service returned an invalid response."
        case .httpStatus(let statusCode):
            return "Voice file request failed (\(statusCode))."
        case .invalidAudioData:
            return "Voice file is invalid or empty."
        }
    }
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

private protocol MessageTimestampProviding {
    func timestampLabel(for message: PersonaMessage, previous: PersonaMessage?) -> String?
}

private struct RealTimeMessageTimestampProvider: MessageTimestampProviding {
    func timestampLabel(for message: PersonaMessage, previous: PersonaMessage?) -> String? {
        let gap: TimeInterval = 5 * 60
        if let previous, message.createdAt.timeIntervalSince(previous.createdAt) < gap {
            return nil
        }

        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.doesRelativeDateFormatting = true
        formatter.timeStyle = .short
        formatter.dateStyle = Calendar.current.isDateInToday(message.createdAt) ? .none : .medium
        return formatter.string(from: message.createdAt)
    }
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

private struct EffectVideoView: UIViewControllerRepresentable {
    let player: AVPlayer

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.showsPlaybackControls = false
        controller.videoGravity = .resizeAspectFill
        controller.view.backgroundColor = .clear
        return controller
    }

    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {
        uiViewController.player = player
    }
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
