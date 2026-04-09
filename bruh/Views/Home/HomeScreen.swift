import SwiftUI
import UIKit

enum AppDestination: Hashable {
    case feed
    case imessage
    case contacts
    case album
    case settings
}

struct HomeScreen: View {
    let onNavigate: (AppDestination) -> Void
    let messageUnreadCount: Int
    let momentsUnreadCount: Int
    let hasNewAlbumBadge: Bool
    @State private var isVoiceBubblePlaying = false

    private let quickApps: [HomeQuickApp] = [
        .init(name: "鸽们", imageAsset: "Icon_contacts", destination: .contacts),
        .init(name: "消息", imageAsset: "Icon_message", destination: .imessage, badgeCount: 8),
        .init(name: "日常", imageAsset: "Icon_moments", destination: .feed),
        .init(name: "相册", imageAsset: "Icon_album", destination: .album),
        .init(name: "小红书", imageAsset: "Icon_xhs", destination: nil),
        .init(name: "影石", imageAsset: "Icon_insta", destination: nil),
        .init(name: "鸿蒙", placeholderText: "鸿", placeholderColors: [Color(red: 0.95, green: 0.60, blue: 0.36), Color(red: 0.90, green: 0.38, blue: 0.22)], destination: nil),
        .init(name: "极客公园", placeholderText: "极", placeholderColors: [Color(red: 0.95, green: 0.45, blue: 0.67), Color(red: 0.79, green: 0.20, blue: 0.46)], destination: nil),
    ]

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
        .background(AppTheme.messagesBackground.ignoresSafeArea())
    }

    private var dateTimePanel: some View {
        VStack(spacing: 4) {
            Text("星期三，4月8日")
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(Color.black.opacity(0.50))

            Text("11:30")
                .font(.system(size: 90, weight: .black, design: .rounded))
                .foregroundStyle(Color.black.opacity(0.92))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
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
                messageSnippet(name: "Donald Trump", text: "FAKE NEWS 鸽们！我们的经济要起飞了。", time: "2分")
                messageSnippet(name: "Elon Musk", text: "火星计划更新：节奏比预期还快。", time: "15分")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .background(Color.white.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func messageSnippet(name: String, text: String, time: String) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(Color.black.opacity(0.85))
                .frame(width: 42, height: 42)
                .overlay {
                    Text(String(name.prefix(1)))
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.white)
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
            // Audio placeholder: toggle visual state only.
            withAnimation(.easeInOut(duration: 0.18)) {
                isVoiceBubblePlaying.toggle()
            }
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

                Text("--:--")
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
                    guard let destination = app.destination else { return }
                    onNavigate(destination)
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
}

private struct HomeQuickApp: Identifiable {
    let id = UUID()
    let name: String
    var imageAsset: String? = nil
    var placeholderText: String? = nil
    var placeholderColors: [Color]? = nil
    let destination: AppDestination?
    var badgeCount: Int? = nil
    var badgeText: String? = nil
}

#Preview {
    HomeScreen(onNavigate: { _ in }, messageUnreadCount: 3, momentsUnreadCount: 5, hasNewAlbumBadge: true)
}
