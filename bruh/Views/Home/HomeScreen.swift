import SwiftUI
import UIKit
import AVFoundation

enum AppDestination: Hashable {
    case feed
    case imessage
    case contacts
    case album
    case settings
}

struct HomeScreen: View {
    @Environment(\.openURL) private var openURL
    let onNavigate: (AppDestination) -> Void
    let messageUnreadCount: Int
    let momentsUnreadCount: Int
    let hasNewAlbumBadge: Bool
    let pendingInvitationCount: Int
    let messagePreviews: [HomeMessagePreview]
    @State private var isVoiceBubblePlaying = false
    @State private var voicePlayer: AVAudioPlayer?
    @State private var voiceDurationLabel = "--:--"
    @State private var voicePlayerDelegate: HomeVoicePlayerDelegate?

    private var quickApps: [HomeQuickApp] {
        [
            .init(name: "鸽们", imageAsset: "Icon_contacts", destination: .contacts, badgeCount: pendingInvitationCount > 0 ? pendingInvitationCount : nil),
            .init(name: "消息", imageAsset: "Icon_message", destination: .imessage, badgeCount: messageUnreadCount),
            .init(name: "日常", imageAsset: "Icon_moments", destination: .feed, badgeCount: momentsUnreadCount),
            .init(name: "相册", imageAsset: "Icon_album", destination: .album, badgeText: hasNewAlbumBadge ? "新" : nil),
        .init(
            name: "小红书",
            imageAsset: "Icon_xhs",
            destination: nil,
            deepLinkURL: URL(string: "xhsdiscover://home"),
            fallbackWebURL: URL(string: "https://www.xiaohongshu.com")
        ),
        .init(
            name: "影石",
            imageAsset: "Icon_insta",
            destination: nil,
            deepLinkURL: URL(string: "insta360://"),
            fallbackWebURL: URL(string: "https://www.insta360.com")
        ),
        .init(
            name: "鸿蒙",
            imageAsset: "Icon_harmony",
            destination: nil,
            fallbackWebURL: URL(string: "https://www.harmonyos.com/")
        ),
        .init(
            name: "极客公园",
            imageAsset: "Icon_geek",
            destination: nil,
            fallbackWebURL: URL(string: "https://www.geekpark.net/")
        ),
        ]
    }

    private var dockApps: [HomeQuickApp] {
        [
            .init(name: "鸽们", imageAsset: "Icon_contacts", destination: .contacts),
            .init(name: "消息", imageAsset: "Icon_message", destination: .imessage, badgeCount: messageUnreadCount),
            .init(name: "日常", imageAsset: "Icon_moments", destination: .feed, badgeCount: momentsUnreadCount),
            .init(name: "相册", imageAsset: "Icon_album", destination: .album, badgeText: hasNewAlbumBadge ? "新" : nil),
        ]
    }

    private let iconTileSize: CGFloat = 64
    private let iconCornerRadius: CGFloat = 16
    private let fourColumnLayout: [GridItem] = Array(repeating: GridItem(.flexible(), spacing: 14), count: 4)
    private let homeBackgroundColor = Color(red: 0.93, green: 0.89, blue: 0.82)

    var body: some View {
        VStack(spacing: 16) {
            dateTimePanel
                .padding(.top, 6)

            messagesWidget

            VStack(spacing: 0) {
                quickAppsGrid
                Spacer(minLength: 0)
                voiceBubbleWidget
                Spacer(minLength: 0)
                dock
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(homeBackgroundColor.ignoresSafeArea())
        .onAppear {
            prepareVoiceIfNeeded()
        }
        .onDisappear {
            voicePlayer?.stop()
            isVoiceBubblePlaying = false
        }
    }

    private var dateTimePanel: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(spacing: 4) {
                Text(homeDateString(from: context.date))
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(Color.black.opacity(0.50))

                Text(homeTimeString(from: context.date))
                    .font(.system(size: 90, weight: .black, design: .rounded))
                    .foregroundStyle(Color.black.opacity(0.92))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var messagesWidget: some View {
        VStack(spacing: 12) {
            HStack {
                HStack(spacing: 8) {
                    Text("鸽们")
                        .font(.system(size: 22, weight: .black, design: .rounded))
                        .foregroundStyle(Color.black.opacity(0.88))
                        .italic()

                    Text("消息")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.black.opacity(0.35))
                }

                Spacer()

                Button {
                    onNavigate(.imessage)
                } label: {
                    Text("查看全部")
                        .font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(.plain)
            }

            VStack(spacing: 10) {
                if messagePreviews.isEmpty {
                    Text("暂无新消息")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.black.opacity(0.40))
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ForEach(Array(messagePreviews.prefix(2).enumerated()), id: \.offset) { _, preview in
                        messageSnippet(
                            name: preview.name,
                            text: preview.text,
                            time: preview.time,
                            avatarAsset: preview.avatarAsset,
                            avatarBackground: preview.avatarBackground
                        )
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .background(Color.white.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func messageSnippet(name: String, text: String, time: String, avatarAsset: String? = nil, avatarBackground: Color = Color.black.opacity(0.85)) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(avatarBackground)
                .frame(width: 42, height: 42)
                .overlay {
                    if let avatarAsset, UIImage(named: avatarAsset) != nil {
                        Image(avatarAsset)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 42, height: 42)
                            .clipShape(Circle())
                    } else {
                        Text(String(name.prefix(1)))
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }

            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.black.opacity(0.88))

                Text(text)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.black.opacity(0.40))
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            Text(time)
                .font(.system(size: 12))
                .foregroundStyle(Color.black.opacity(0.30))
        }
    }

    private var voiceBubbleWidget: some View {
        Button {
            toggleVoicePlayback()
        } label: {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(Color.black.opacity(0.10))
                        .frame(width: 34, height: 34)

                    Image(systemName: isVoiceBubblePlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.black.opacity(0.76))
                        .offset(x: isVoiceBubblePlaying ? 0 : 1)
                }

                HStack(spacing: 4) {
                    ForEach(0..<16, id: \.self) { index in
                        Capsule()
                            .fill(Color.black.opacity(isVoiceBubblePlaying ? 0.44 : 0.30))
                            .frame(
                                width: 3,
                                height: isVoiceBubblePlaying
                                    ? CGFloat(8 + ((index * 7) % 14))
                                    : CGFloat(8 + ((index * 5) % 10))
                            )
                    }
                }
                .frame(height: 24, alignment: .center)

                Spacer(minLength: 0)

                Text(isVoiceBubblePlaying ? "播放中" : "语音消息")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.black.opacity(0.56))

                Text(voiceDurationLabel)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.black.opacity(0.38))
            }
            .padding(.horizontal, 12)
            .frame(height: 68)
            .frame(maxWidth: 360)
            .background(Color.white.opacity(0.72))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.black.opacity(0.05), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private var quickAppsGrid: some View {
        LazyVGrid(columns: fourColumnLayout, spacing: 14) {
            ForEach(quickApps) { app in
                Button {
                    if let destination = app.destination {
                        onNavigate(destination)
                        return
                    }

                    openExternalApp(for: app)
                } label: {
                    VStack(spacing: 7) {
                        ZStack(alignment: .topTrailing) {
                            appIconTile(app)

                            if let badgeText = app.badgeText {
                                badgeLabel(text: badgeText)
                                    .offset(x: 8, y: -8)
                            } else if let badgeCount = app.badgeCount, badgeCount > 0 {
                                badgeLabel(text: badgeCount > 99 ? "99+" : "\(badgeCount)")
                                    .offset(x: 8, y: -8)
                            }
                        }

                        Text(app.name)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Color.black.opacity(0.64))
                            .lineLimit(1)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func badgeLabel(text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .frame(height: 18)
            .background(Color.red)
            .clipShape(Capsule())
            .overlay {
                Capsule().stroke(Color.white, lineWidth: 1.2)
            }
    }

    private var dock: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color.white.opacity(0.55))
                .overlay {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(Color.white.opacity(0.35), lineWidth: 0.8)
                }

            LazyVGrid(columns: fourColumnLayout, spacing: 14) {
                ForEach(dockApps) { app in
                    Button {
                        guard let destination = app.destination else { return }
                        onNavigate(destination)
                    } label: {
                        ZStack(alignment: .topTrailing) {
                            appIconTile(app)

                            if let badgeText = app.badgeText {
                                badgeLabel(text: badgeText)
                                    .offset(x: 8, y: -8)
                            } else if let badgeCount = app.badgeCount, badgeCount > 0 {
                                badgeLabel(text: badgeCount > 99 ? "99+" : "\(badgeCount)")
                                    .offset(x: 8, y: -8)
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
        }
        .frame(height: 96)
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private func appIconTile(_ app: HomeQuickApp) -> some View {
        RoundedRectangle(cornerRadius: iconCornerRadius, style: .continuous)
            .fill(iconBackground(for: app))
            .frame(width: iconTileSize, height: iconTileSize)
            .overlay {
                if let imageAsset = app.imageAsset, UIImage(named: imageAsset) != nil {
                    Image(imageAsset)
                        .resizable()
                        .scaledToFill()
                        .frame(width: iconTileSize, height: iconTileSize)
                        .clipShape(RoundedRectangle(cornerRadius: iconCornerRadius, style: .continuous))
                } else if let placeholderText = app.placeholderText {
                    Text(placeholderText)
                        .font(.system(size: 30, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: iconCornerRadius, style: .continuous)
                    .stroke(Color.white.opacity(0.18), lineWidth: 0.8)
            }
    }

    private func iconBackground(for app: HomeQuickApp) -> some ShapeStyle {
        LinearGradient(
            colors: app.placeholderColors ?? [Color.black.opacity(0.86), Color.black.opacity(0.68)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private func toggleVoicePlayback() {
        prepareVoiceIfNeeded()
        guard let voicePlayer else { return }

        withAnimation(.easeInOut(duration: 0.18)) {
            if voicePlayer.isPlaying {
                voicePlayer.pause()
                isVoiceBubblePlaying = false
            } else {
                if !voicePlayer.play() {
                    // Retry once with a fresh player/session in case session state changed.
                    self.voicePlayer = nil
                    prepareVoiceIfNeeded()
                    if let retryPlayer = self.voicePlayer {
                        isVoiceBubblePlaying = retryPlayer.play()
                    } else {
                        isVoiceBubblePlaying = false
                    }
                } else {
                    isVoiceBubblePlaying = true
                }
            }
        }
    }

    private func prepareVoiceIfNeeded() {
        if let existing = voicePlayer {
            voiceDurationLabel = formatDuration(existing.duration)
            if !existing.isPlaying {
                isVoiceBubblePlaying = false
            }
            return
        }

        configureAudioSessionIfNeeded()

        guard let url = Bundle.main.url(forResource: "ending", withExtension: "wav") else {
            voiceDurationLabel = "--:--"
            return
        }

        do {
            let player = try AVAudioPlayer(contentsOf: url)
            let delegate = HomeVoicePlayerDelegate {
                isVoiceBubblePlaying = false
            }
            player.delegate = delegate
            player.prepareToPlay()
            player.volume = 1
            voicePlayer = player
            voicePlayerDelegate = delegate
            voiceDurationLabel = formatDuration(player.duration)
        } catch {
            voiceDurationLabel = "--:--"
        }
    }

    private func configureAudioSessionIfNeeded() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .default, options: [])
            try session.setActive(true, options: [])
        } catch {
            return
        }
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let total = max(0, Int(duration.rounded()))
        let minutes = total / 60
        let seconds = total % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    private func openExternalApp(for app: HomeQuickApp) {
        guard let deepLinkURL = app.deepLinkURL else {
            guard let fallbackWebURL = app.fallbackWebURL else { return }
            openURL(fallbackWebURL)
            return
        }
        openURL(deepLinkURL) { accepted in
            guard !accepted, let fallbackWebURL = app.fallbackWebURL else { return }
            openURL(fallbackWebURL)
        }
    }

    private func homeDateString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.calendar = .current
        formatter.setLocalizedDateFormatFromTemplate("EEEE MMMMd")
        return formatter.string(from: date)
    }

    private func homeTimeString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.calendar = .current
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}

private final class HomeVoicePlayerDelegate: NSObject, AVAudioPlayerDelegate {
    private let onFinish: () -> Void

    init(onFinish: @escaping () -> Void) {
        self.onFinish = onFinish
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        onFinish()
    }

    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        onFinish()
    }
}

private struct HomeQuickApp: Identifiable {
    let id = UUID()
    let name: String
    var imageAsset: String? = nil
    var placeholderText: String? = nil
    var placeholderColors: [Color]? = nil
    let destination: AppDestination?
    var deepLinkURL: URL? = nil
    var fallbackWebURL: URL? = nil
    var badgeCount: Int? = nil
    var badgeText: String? = nil
}

#Preview {
    HomeScreen(
        onNavigate: { _ in },
        messageUnreadCount: 3,
        momentsUnreadCount: 5,
        hasNewAlbumBadge: true,
        pendingInvitationCount: 2,
        messagePreviews: [
            .init(name: "特离谱", text: "今天这条新闻太离谱了。", time: "2分", avatarAsset: "Avatar_Trump"),
            .init(name: "马期克", text: "火箭和 AI 同时推进。", time: "15分", avatarAsset: "Avatar_Elon"),
        ]
    )
}

struct HomeMessagePreview {
    let name: String
    let text: String
    let time: String
    var avatarAsset: String? = nil
    var avatarBackground: Color = Color.black.opacity(0.85)
}
