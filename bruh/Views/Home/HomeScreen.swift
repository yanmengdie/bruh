import SwiftUI

struct AppItem: Identifiable {
    let id = UUID()
    let name: String
    let icon: String
    let iconColor: Color
    let destination: AppDestination?
    let unreadCount: Int
    let badgeText: String?
}

enum AppDestination: Equatable {
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

    private var gridApps: [AppItem] {
        [
            AppItem(name: "Contacts", icon: "person.crop.circle.fill", iconColor: .green, destination: .contacts, unreadCount: 0, badgeText: nil),
            AppItem(name: "Messages", icon: "message.fill", iconColor: .green, destination: .imessage, unreadCount: messageUnreadCount, badgeText: nil),
            AppItem(name: "朋友圈", icon: "globe", iconColor: Color(red: 1.0, green: 0.72, blue: 0.62), destination: .feed, unreadCount: momentsUnreadCount, badgeText: nil),
            AppItem(name: "Album", icon: "photo.on.rectangle.angled", iconColor: .red, destination: .album, unreadCount: 0, badgeText: hasNewAlbumBadge ? "NEW" : nil),
            AppItem(name: "Settings", icon: "gearshape.fill", iconColor: Color(red: 0.55, green: 0.62, blue: 0.95), destination: .settings, unreadCount: 0, badgeText: nil),
        ]
    }

    private var dockApps: [AppItem] {
        [
            AppItem(name: "Contacts", icon: "person.crop.circle.fill", iconColor: .green, destination: .contacts, unreadCount: 0, badgeText: nil),
            AppItem(name: "Messages", icon: "message.fill", iconColor: .green, destination: .imessage, unreadCount: messageUnreadCount, badgeText: nil),
            AppItem(name: "朋友圈", icon: "globe", iconColor: Color(red: 1.0, green: 0.72, blue: 0.62), destination: .feed, unreadCount: momentsUnreadCount, badgeText: nil),
            AppItem(name: "Album", icon: "photo.on.rectangle.angled", iconColor: .red, destination: .album, unreadCount: 0, badgeText: nil),
        ]
    }

    var body: some View {
        GeometryReader { proxy in
            let layout = makeLayout(for: proxy.size)

            VStack(spacing: 0) {
                LazyVGrid(columns: layout.columns, spacing: layout.gridRowSpacing) {
                    ForEach(gridApps) { app in
                        AppIconView(app: app, iconSize: layout.gridIconSize) {
                            guard let destination = app.destination else { return }
                            onNavigate(destination)
                        }
                    }
                }
                .padding(.horizontal, layout.gridHorizontalPadding)
                .padding(.top, layout.gridTopPadding)

                Spacer(minLength: 0)

                dock(iconSize: layout.dockIconSize, iconSpacing: layout.dockIconSpacing)
                    .padding(.horizontal, layout.dockHorizontalPadding)
                    .padding(.bottom, layout.dockBottomPadding)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .safeAreaPadding(.top, layout.safeTopPadding)
            .background {
                ZStack {
                    LinearGradient(
                        colors: [
                            Color(red: 0.17, green: 0.22, blue: 0.52),
                            Color(red: 0.42, green: 0.35, blue: 0.75),
                            Color(red: 0.94, green: 0.47, blue: 0.52),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )

                    Circle()
                        .fill(Color.white.opacity(0.16))
                        .blur(radius: 60)
                        .frame(width: 220, height: 220)
                        .offset(x: -70, y: -180)

                    Circle()
                        .fill(Color.blue.opacity(0.18))
                        .blur(radius: 80)
                        .frame(width: 260, height: 260)
                        .offset(x: 90, y: 220)
                }
                .ignoresSafeArea()
            }
        }
    }

    private func dock(iconSize: CGFloat, iconSpacing: CGFloat) -> some View {
        HStack(spacing: iconSpacing) {
            ForEach(dockApps) { app in
                AppIconView(app: app, iconSize: iconSize, labelHidden: true) {
                    guard let destination = app.destination else { return }
                    onNavigate(destination)
                }
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 18)
        .background(.ultraThinMaterial.opacity(0.95))
        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
    }

    private func makeLayout(for size: CGSize) -> HomeLayout {
        let isWidePhone = size.width >= 400
        let iconSize = min(62, max(56, size.width * 0.15))
        let dockIconSize = iconSize - 2

        return HomeLayout(
            columns: Array(repeating: GridItem(.flexible(), spacing: isWidePhone ? 14 : 16), count: isWidePhone ? 5 : 4),
            gridIconSize: iconSize,
            dockIconSize: dockIconSize,
            gridRowSpacing: isWidePhone ? 22 : 24,
            gridHorizontalPadding: isWidePhone ? 16 : 18,
            gridTopPadding: isWidePhone ? 16 : 12,
            safeTopPadding: isWidePhone ? 12 : 8,
            dockIconSpacing: isWidePhone ? 18 : 22,
            dockHorizontalPadding: isWidePhone ? 12 : 14,
            dockBottomPadding: isWidePhone ? 10 : 6
        )
    }
}

private struct HomeLayout {
    let columns: [GridItem]
    let gridIconSize: CGFloat
    let dockIconSize: CGFloat
    let gridRowSpacing: CGFloat
    let gridHorizontalPadding: CGFloat
    let gridTopPadding: CGFloat
    let safeTopPadding: CGFloat
    let dockIconSpacing: CGFloat
    let dockHorizontalPadding: CGFloat
    let dockBottomPadding: CGFloat
}

private struct AppIconView: View {
    let app: AppItem
    var iconSize: CGFloat = 60
    var labelHidden: Bool = false
    let onTap: () -> Void

    @State private var isPressed = false

    var body: some View {
        Button {
            isPressed = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                isPressed = false
                onTap()
            }
        } label: {
            VStack(spacing: 6) {
                ZStack(alignment: .topTrailing) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(app.iconColor.gradient)
                            .frame(width: iconSize, height: iconSize)
                            .overlay {
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .stroke(.white.opacity(0.18), lineWidth: 0.8)
                            }
                            .shadow(color: .black.opacity(0.22), radius: 8, y: 3)

                        Image(systemName: app.icon)
                            .font(.system(size: iconSize * 0.42, weight: .medium))
                            .foregroundStyle(.white)
                    }

                    if let badgeText = app.badgeText {
                        Text(badgeText)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .frame(height: 20)
                            .background(Color.orange)
                            .clipShape(Capsule())
                            .overlay {
                                Capsule().stroke(.white, lineWidth: 1.5)
                            }
                            .offset(x: 10, y: -8)
                    } else if app.unreadCount > 0 {
                        Text(app.unreadCount > 99 ? "99+" : "\(app.unreadCount)")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, app.unreadCount > 9 ? 6 : 5)
                            .frame(height: 20)
                            .background(Color.red)
                            .clipShape(Capsule())
                            .overlay {
                                Capsule().stroke(.white, lineWidth: 1.5)
                            }
                            .offset(x: 8, y: -8)
                    }
                }

                if !labelHidden {
                    Text(app.name)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
                        .lineLimit(1)
                }
            }
        }
        .buttonStyle(.plain)
        .scaleEffect(isPressed ? 0.9 : 1)
        .animation(.spring(response: 0.22, dampingFraction: 0.6), value: isPressed)
    }
}

#Preview {
    HomeScreen(onNavigate: { _ in }, messageUnreadCount: 3, momentsUnreadCount: 5, hasNewAlbumBadge: true)
}
