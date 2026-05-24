import SwiftUI
import SwiftData
import AVFoundation
import AVKit
import SafariServices
import UIKit

struct MessageDetailView: View {
    private static let bottomScrollAnchor = "message-detail-bottom-scroll-anchor"

    @Environment(\.modelContext) private var modelContext
    @Query private var messages: [PersonaMessage]
    @Query(sort: [SortDescriptor(\Contact.name, order: .forward)]) private var contacts: [Contact]

    let thread: MessageThread
    let service: MessageService
    private let timestampProvider: any MessageTimestampProviding

    @State private var draft = ""
    @State private var isSending = false
    @State private var errorMessage: String?
    @StateObject private var webPreviewStore = OpenGraphPreviewStore()
    @StateObject private var audioPlayback = MessageAudioPlaybackController()
    @State private var presentedSourceURL: URL?
    @State private var isPresentingSafari = false
    @State private var effectPlayer: AVPlayer?
    @State private var isShowingExcitedEffect = false
    @State private var hasCheckedEntryEffect = false
    @State private var hasCompletedInitialScroll = false
    @State private var entryUnreadCount = 0
    @FocusState private var isComposerFocused: Bool
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

                        Color.clear
                            .frame(height: 1)
                            .id(Self.bottomScrollAnchor)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
                .onTapGesture {
                    isComposerFocused = false
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .onAppear {
                scheduleScrollToBottom(with: proxy, animated: false)
            }
            .task(id: latestMessageId) {
                guard latestMessageId != nil else { return }
                let shouldAnimate = hasCompletedInitialScroll
                scheduleScrollToBottom(with: proxy, animated: shouldAnimate)
                hasCompletedInitialScroll = true
            }
            .onChange(of: isSending) { _, sending in
                guard sending else { return }
                scheduleScrollToBottom(with: proxy)
            }
            .onChange(of: isComposerFocused) { _, focused in
                guard focused else { return }
                scheduleScrollToBottom(with: proxy)
            }
        }
        .background(AppTheme.messagesBackground)
        .enableUnifiedSwipeBack()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                detailNavigationTitle
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            composerBar
        }
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
            markThreadAsRead()
        }
        .task(id: latestIncomingMessageId) {
            guard latestIncomingMessageId != nil else { return }
            markThreadAsRead()
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

    private var detailNavigationTitle: some View {
        VStack(spacing: 1) {
            Text(displayName)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)

            Text("鸽们 · \(presenceText)")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
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
        return secondsSinceLastMessage <= threshold ? "在线" : "离线"
    }

    private var latestConversationDate: Date {
        messages.last?.createdAt ?? thread.lastMessageAt
    }

    private var currentUnreadCount: Int {
        let incomingMessages = messages.filter(\.isIncoming)
        guard !incomingMessages.isEmpty else { return max(0, thread.unreadCount) }

        let cutoff = thread.lastReadAt ?? .distantPast
        return incomingMessages.reduce(0) { count, message in
            count + (message.createdAt > cutoff ? 1 : 0)
        }
    }

    private var latestIncomingMessageId: String? {
        messages.last(where: \.isIncoming)?.id
    }

    private var latestMessageId: String? {
        messages.last?.id
    }

    private var composerBar: some View {
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
                .disabled(isSending || trimmedDraft.isEmpty)

                TextField("给\(displayName)发消息...", text: $draft)
                    .focused($isComposerFocused)
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
                        .foregroundColor(trimmedDraft.isEmpty ? .secondary : .blue)
                }
                .buttonStyle(.plain)
                .disabled(isSending || trimmedDraft.isEmpty)
            }
            .padding(.horizontal, 12)
            .padding(.top, 4)
            .padding(.bottom, 8)
        }
        .background(.ultraThinMaterial)
    }

    private func markThreadAsRead() {
        try? service.markThreadRead(personaId: thread.personaId, modelContext: modelContext)
    }



    private func avatarCircle(size: CGFloat) -> some View {
        let persona = MessagePersonaHelper.persona(for: thread.personaId, contacts: contacts)
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
        let text = trimmedDraft
        guard !text.isEmpty, !isSending else { return }

        isComposerFocused = false
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

    private var trimmedDraft: String {
        draft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func scrollToBottom(
        with proxy: ScrollViewProxy,
        animated: Bool = true
    ) {
        let action = {
            proxy.scrollTo(Self.bottomScrollAnchor, anchor: .bottom)
        }

        if animated {
            withAnimation {
                action()
            }
        } else {
            action()
        }
    }

    private func scheduleScrollToBottom(
        with proxy: ScrollViewProxy,
        animated: Bool = true
    ) {
        DispatchQueue.main.async {
            scrollToBottom(with: proxy, animated: animated)
        }
    }

    private var waitingMessageRow: some View {
        HStack(alignment: .bottom, spacing: AppTheme.messageIncomingAvatarBubbleSpacing) {
            incomingAvatar
            TypingIndicatorBubble(themeColor: MessagePersonaHelper.persona(for: thread.personaId, contacts: contacts).tint)
            Spacer(minLength: 40)
        }
    }

    private var inlineErrorMessage: String? {
        if let errorMessage, !errorMessage.isEmpty {
            return errorMessage
        }
        return audioPlayback.lastErrorMessage
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
        let personaTheme = MessagePersonaHelper.persona(for: thread.personaId, contacts: contacts).tint
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
        VStack(alignment: isIncoming ? .leading : .trailing, spacing: 6) {
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
            case .audio(let url, let duration, let messageId):
                voiceMessageCard(
                    url: url,
                    duration: duration,
                    messageId: messageId,
                    isIncoming: isIncoming,
                    deliveryState: deliveryState,
                    themeColor: themeColor
                )
            }
        }
    }

    private func parseContent(from message: PersonaMessage) -> MessageContent {
        if message.audioOnly,
           let audioUrl = RemoteMediaPolicy.normalizedAssetURL(message.audioUrl) {
            let resolvedDuration = audioPlayback.resolvedDurations[message.id] ?? message.audioDuration
            return .audio(
                audioUrl,
                duration: resolvedDuration,
                messageId: message.id
            )
        }

        if let imageUrl = RemoteMediaPolicy.normalizedAssetURL(message.imageUrl) {
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
                Text("发送失败")
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
            }
        }
    }

    private func voiceMessageCard(
        url: URL,
        duration: TimeInterval?,
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
                    duration: effectiveDuration
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
                Text("发送失败")
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
                Text("发送失败")
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
        HStack(spacing: 4) {
            reactionEmojiText(reaction.emoji)
            Text(reaction.mood)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
        }
            .padding(.leading, 2)
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

    private func reactionEmojiText(_ emoji: String) -> some View {
        Text(verbatim: emoji)
            .font(.system(size: 15))
    }
}

enum MessageContent {
    case text(String, imageUrl: URL?)
    case webPreview(URL)
    case audio(URL, duration: TimeInterval?, messageId: String)
}

struct TypingIndicatorBubble: View {
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
