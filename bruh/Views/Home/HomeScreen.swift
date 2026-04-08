import SwiftUI

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

    private let quickApps: [HomeQuickApp] = [
        .init(name: "消息", icon: "message.fill", colors: [Color.black.opacity(0.88), Color.black.opacity(0.72)], destination: .imessage, badgeCount: 8),
        .init(name: "朋友圈", icon: "flame.fill", colors: [Color(red: 1.0, green: 0.41, blue: 0.42), Color(red: 0.85, green: 0.14, blue: 0.28)], destination: .feed),
        .init(name: "群聊", icon: "ellipsis.bubble.fill", colors: [Color(red: 0.61, green: 0.60, blue: 0.98), Color(red: 0.43, green: 0.40, blue: 0.90)], destination: .contacts),
        .init(name: "资讯", icon: "newspaper.fill", colors: [Color(red: 0.94, green: 0.80, blue: 0.37), Color(red: 0.85, green: 0.66, blue: 0.15)], destination: .album),
        .init(name: "小红书", icon: "mic.fill", colors: [Color(red: 0.27, green: 0.86, blue: 0.74), Color(red: 0.08, green: 0.72, blue: 0.58)], destination: nil),
        .init(name: "影石", icon: "chart.bar.fill", colors: [Color(red: 0.39, green: 0.64, blue: 0.98), Color(red: 0.18, green: 0.43, blue: 0.84)], destination: nil),
        .init(name: "云服务", icon: "trophy.fill", colors: [Color(red: 1.0, green: 0.62, blue: 0.42), Color(red: 0.96, green: 0.41, blue: 0.23)], destination: nil),
        .init(name: "极客公园", icon: "music.note", colors: [Color(red: 0.97, green: 0.39, blue: 0.65), Color(red: 0.83, green: 0.15, blue: 0.43)], destination: nil),
    ]

    private var dockApps: [HomeQuickApp] {
        [
            .init(name: "联系人", icon: "person.crop.circle.fill", colors: [.green.opacity(0.92), .green.opacity(0.72)], destination: .contacts),
            .init(name: "消息", icon: "message.fill", colors: [.green.opacity(0.92), .green.opacity(0.72)], destination: .imessage, badgeCount: messageUnreadCount),
            .init(name: "朋友圈", icon: "globe", colors: [Color(red: 1.0, green: 0.72, blue: 0.62), Color(red: 1.0, green: 0.55, blue: 0.55)], destination: .feed, badgeCount: momentsUnreadCount),
            .init(name: "相册", icon: "photo.on.rectangle.angled", colors: [.red.opacity(0.92), .red.opacity(0.72)], destination: .album, badgeText: hasNewAlbumBadge ? "新" : nil),
        ]
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 16) {
                statusHeader
                    .padding(.top, 8)

                dateTimePanel

                messagesWidget

                quickAppsGrid

                marketAndMusicWidgets

                dock
                    .padding(.top, 6)
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 18)
        }
        .background(AppTheme.messagesBackground.ignoresSafeArea())
    }

    private var statusHeader: some View {
        HStack {
            Text("11:30")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.black.opacity(0.88))

            Spacer()

            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.black)
                .frame(width: 120, height: 34)

            Spacer()

            HStack(spacing: 4) {
                ForEach(0..<4, id: \.self) { _ in
                    Circle()
                        .fill(Color.black.opacity(0.9))
                        .frame(width: 8, height: 8)
                }
                Text("WiFi")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.black.opacity(0.88))
                Text("🔋")
                    .font(.system(size: 14))
            }
        }
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
                messageSnippet(name: "Donald Trump", text: "FAKE NEWS bro！我们的经济要起飞了。", time: "2分")
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

    private var quickAppsGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: 4), spacing: 14) {
            ForEach(quickApps) { app in
                Button {
                    guard let destination = app.destination else { return }
                    onNavigate(destination)
                } label: {
                    VStack(spacing: 7) {
                        ZStack(alignment: .topTrailing) {
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: app.colors,
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(height: 76)

                            Image(systemName: app.icon)
                                .font(.system(size: 30, weight: .medium))
                                .foregroundStyle(.white)

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

    private var marketAndMusicWidgets: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 10) {
                Text("股市")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Color.black.opacity(0.88))

                marketRow(symbol: "AAPL", change: "+2.41%", isUp: true)
                marketRow(symbol: "TSLA", change: "-1.82%", isUp: false)
                marketRow(symbol: "NVDA", change: "+5.12%", isUp: true)

                Spacer(minLength: 0)

                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.green.opacity(0.14))
                    .frame(height: 56)
                    .overlay(alignment: .leading) {
                        Path { path in
                            path.move(to: CGPoint(x: 8, y: 50))
                            path.addLine(to: CGPoint(x: 44, y: 42))
                            path.addLine(to: CGPoint(x: 84, y: 34))
                            path.addLine(to: CGPoint(x: 126, y: 24))
                            path.addLine(to: CGPoint(x: 164, y: 14))
                        }
                        .stroke(Color.green, lineWidth: 2.5)
                    }
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 190, maxHeight: 190, alignment: .topLeading)
            .background(Color.white.opacity(0.72))
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))

            VStack(alignment: .leading, spacing: 8) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white)
                    .frame(width: 58, height: 58)
                    .overlay {
                        Image(systemName: "music.note")
                            .font(.system(size: 22))
                            .foregroundStyle(Color.pink)
                    }

                Text("正在播放")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.pink.opacity(0.88))

                Text("Shake It Off")
                    .font(.system(size: 21, weight: .bold))
                    .foregroundStyle(Color.black.opacity(0.88))
                    .lineLimit(1)

                Text("Taylor Swift")
                    .font(.system(size: 15))
                    .foregroundStyle(Color.black.opacity(0.36))

                HStack(spacing: 22) {
                    Text("⏮")
                    Text("▶")
                    Text("⏭")
                }
                .font(.system(size: 20))
                .foregroundStyle(Color.pink.opacity(0.88))

                Rectangle()
                    .fill(Color.black.opacity(0.10))
                    .frame(height: 4)
                    .overlay(alignment: .leading) {
                        Rectangle()
                            .fill(Color.pink.opacity(0.92))
                            .frame(width: 84, height: 4)
                    }
                    .clipShape(Capsule())
            }
            .padding(12)
            .frame(width: 150)
            .frame(minHeight: 190, maxHeight: 190, alignment: .topLeading)
            .background(Color.white.opacity(0.72))
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
    }

    private func marketRow(symbol: String, change: String, isUp: Bool) -> some View {
        HStack {
            Text(symbol)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(Color.black.opacity(0.85))

            Spacer()

            Text(change)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .frame(height: 24)
                .background(isUp ? Color.green : Color.red)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
    }

    private var dock: some View {
        HStack(spacing: 20) {
            ForEach(dockApps) { app in
                Button {
                    guard let destination = app.destination else { return }
                    onNavigate(destination)
                } label: {
                    VStack(spacing: 6) {
                        ZStack(alignment: .topTrailing) {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: app.colors,
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 60, height: 60)

                            Image(systemName: app.icon)
                                .font(.system(size: 24, weight: .medium))
                                .foregroundStyle(.white)

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
                            .foregroundStyle(Color.black.opacity(0.62))
                            .lineLimit(1)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity)
        .background(Color.white.opacity(0.65))
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
    }
}

private struct HomeQuickApp: Identifiable {
    let id = UUID()
    let name: String
    let icon: String
    let colors: [Color]
    let destination: AppDestination?
    var badgeCount: Int? = nil
    var badgeText: String? = nil
}

#Preview {
    HomeScreen(onNavigate: { _ in }, messageUnreadCount: 3, momentsUnreadCount: 5, hasNewAlbumBadge: true)
}
