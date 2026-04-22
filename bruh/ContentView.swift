import SwiftUI
import SwiftData
import UIKit

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\MessageThread.lastMessageAt, order: .reverse)]) private var threads: [MessageThread]
    @Query(sort: [SortDescriptor(\ContentDelivery.sortDate, order: .reverse)]) private var deliveries: [ContentDelivery]
    @Query(sort: [SortDescriptor(\PengyouMoment.publishedAt, order: .reverse)]) private var pengyouMoments: [PengyouMoment]
    @Query(sort: [SortDescriptor(\Contact.name, order: .forward)]) private var contacts: [Contact]
    @AppStorage private var hasCompletedOnboarding: Bool
    @AppStorage private var useHomeScreenMode: Bool
    @AppStorage private var lastViewedFeedAtInterval: Double
    @AppStorage private var lastViewedAlbumAtInterval: Double

    @State private var homePath: [AppDestination] = []
    @State private var selectedTab: MainTab = .contacts
    @State private var messageService = MessageService()
    @State private var bootstrapper = AppBootstrapper()

    init(
        userDefaults: UserDefaults = .standard,
        appEnvironment: AppEnvironment = .current
    ) {
        let scopedDefaults = ScopedUserDefaultsStore(
            userDefaults: userDefaults,
            appEnvironment: appEnvironment
        )
        _hasCompletedOnboarding = AppStorage(
            wrappedValue: false,
            scopedDefaults.key("hasCompletedOnboarding"),
            store: userDefaults
        )
        _useHomeScreenMode = AppStorage(
            wrappedValue: true,
            scopedDefaults.key("useHomeScreenMode"),
            store: userDefaults
        )
        _lastViewedFeedAtInterval = AppStorage(
            wrappedValue: 0.0,
            scopedDefaults.key("lastViewedFeedAt"),
            store: userDefaults
        )
        _lastViewedAlbumAtInterval = AppStorage(
            wrappedValue: 0.0,
            scopedDefaults.key("lastViewedAlbumAt"),
            store: userDefaults
        )
    }

    var body: some View {
        Group {
            if hasCompletedOnboarding {
                mainContent
                    .task {
                        await bootstrapper.bootstrap(
                            modelContext: modelContext,
                            messageService: messageService
                        )
                    }
            } else {
                Onboarding {
                    hasCompletedOnboarding = true
                }
            }
        }
    }

    @ViewBuilder
    private var mainContent: some View {
        if useHomeScreenMode {
            homeScreenModeView
        } else {
            tabModeView
        }
    }

    private var homeScreenModeView: some View {
        NavigationStack(path: $homePath) {
            HomeScreen(
                onNavigate: handleHomeNavigation,
                messageUnreadCount: totalUnreadMessages,
                momentsUnreadCount: totalUnreadMoments,
                hasNewAlbumBadge: unseenAlbumCount > 0
            )
            .navigationBarHidden(true)
            .navigationDestination(for: AppDestination.self) { destination in
                switch destination {
                case .contacts:
                    HomeRoutedScreen {
                        ContactsView()
                    }
                case .imessage:
                    HomeRoutedScreen {
                        MessagesScreen(
                            threads: threads,
                            contacts: contacts,
                            service: messageService,
                            backgroundColor: messagesScreenBackground
                        )
                    }
                case .feed:
                    HomeRoutedScreen {
                        FeedView()
                            .onAppear {
                                lastViewedFeedAtInterval = Date().timeIntervalSince1970
                            }
                    }
                case .album:
                    HomeRoutedScreen {
                        AlbumView()
                            .onAppear {
                                lastViewedAlbumAtInterval = Date().timeIntervalSince1970
                            }
                    }
                case .settings:
                    HomeRoutedScreen {
                        SettingsScreen()
                    }
                }
            }
        }
        .enableUnifiedSwipeBack()
        .onAppear(perform: configureNavigationAppearance)
    }

    private var tabModeView: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                ContactsView()
            }
            .enableUnifiedSwipeBack()
            .tabItem {
                Label("鸽们", systemImage: "person.crop.circle.fill")
            }
            .tag(MainTab.contacts)

            NavigationStack {
                MessagesScreen(
                    threads: threads,
                    contacts: contacts,
                    service: messageService,
                    backgroundColor: messagesScreenBackground
                )
            }
            .enableUnifiedSwipeBack()
            .tabItem {
                Label("消息", systemImage: "message.fill")
            }
            .badge(totalUnreadMessages > 0 ? Text("\(totalUnreadMessages)") : nil)
            .tag(MainTab.messages)

            NavigationStack {
                FeedView()
            }
            .enableUnifiedSwipeBack()
            .tabItem {
                Label("日常", systemImage: "globe")
            }
            .badge(totalUnreadMoments > 0 ? Text("\(totalUnreadMoments)") : nil)
            .tag(MainTab.feed)

            NavigationStack {
                AlbumView()
            }
            .enableUnifiedSwipeBack()
            .tabItem {
                Label("相册", systemImage: "photo.on.rectangle.angled")
            }
            .badge(unseenAlbumCount > 0 ? Text("\(unseenAlbumCount)") : nil)
            .tag(MainTab.album)
        }
        .onChange(of: selectedTab) { _, newValue in
            if newValue == .feed {
                lastViewedFeedAtInterval = Date().timeIntervalSince1970
            }
            if newValue == .album {
                lastViewedAlbumAtInterval = Date().timeIntervalSince1970
            }
        }
        .toolbarBackground(AppTheme.messagesBackground, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .onAppear {
            configureTabBarAppearance()
            configureNavigationAppearance()
        }
    }

    private var totalUnreadMessages: Int {
        let acceptedThreads = threads.filter { acceptedPersonaIds.contains($0.personaId) }
        let unreadCountByThreadId = MessageThreadReadState.unreadCountsByThreadId(
            threads: acceptedThreads,
            deliveries: messageDeliveries
        )

        return max(0, acceptedThreads.reduce(0) { count, thread in
            count + (unreadCountByThreadId[thread.id] ?? max(0, thread.unreadCount))
        })
    }

    private var messagesScreenBackground: Color {
        AppTheme.messagesBackground
    }

    private var totalUnreadMoments: Int {
        guard lastViewedFeedAtInterval > 0 else { return pengyouMoments.count }
        let lastViewed = Date(timeIntervalSince1970: lastViewedFeedAtInterval)
        return pengyouMoments.reduce(0) { count, moment in
            count + (moment.publishedAt > lastViewed ? 1 : 0)
        }
    }

    private var unseenAlbumCount: Int {
        guard lastViewedAlbumAtInterval > 0 else { return albumDeliveries.count }
        let lastViewed = Date(timeIntervalSince1970: lastViewedAlbumAtInterval)
        return albumDeliveries.reduce(0) { count, delivery in
            count + (delivery.sortDate > lastViewed ? 1 : 0)
        }
    }

    private var acceptedPersonaIds: Set<String> {
        ContentGraphSelectors.acceptedPersonaIds(from: contacts)
    }

    private var messageDeliveries: [ContentDelivery] {
        ContentGraphSelectors.visibleMessageDeliveries(
            from: deliveries,
            contacts: contacts
        )
    }

    private var albumDeliveries: [ContentDelivery] {
        ContentGraphSelectors.visibleAlbumDeliveries(
            from: deliveries,
            contacts: contacts
        )
    }

    private func handleHomeNavigation(_ destination: AppDestination) {
        homePath.append(destination)
    }

    private func configureNavigationAppearance() {
        let backColor = UIColor(red: 0.52, green: 0.54, blue: 0.57, alpha: 1.0)
        UINavigationBar.appearance().tintColor = backColor
        UIBarButtonItem.appearance().setTitleTextAttributes([.foregroundColor: backColor], for: .normal)
        UIBarButtonItem.appearance().setTitleTextAttributes([.foregroundColor: backColor], for: .highlighted)
    }

    private func configureTabBarAppearance() {
        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor(AppTheme.messagesBackground)
        appearance.shadowColor = UIColor.black.withAlphaComponent(0.05)
        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
    }
}

private struct HomeRoutedScreen<Content: View>: View {
    @Environment(\.dismiss) private var dismiss
    @ViewBuilder let content: Content

    var body: some View {
        content
            .navigationBarBackButtonHidden(true)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    AppBackButton {
                        dismiss()
                    }
                }
            }
            .enableUnifiedSwipeBack()
    }
}

private enum MainTab: Hashable {
    case contacts
    case messages
    case feed
    case album
}

#Preview {
    ContentView()
        .modelContainer(
            for: [
                Persona.self,
                PersonaPost.self,
                PengyouMoment.self,
                SourceItem.self,
                ContentEvent.self,
                ContentDelivery.self,
                MessageThread.self,
                PersonaMessage.self,
                FeedComment.self,
                FeedLike.self,
                FeedInteractionSeedState.self,
                Contact.self,
                UserProfile.self,
            ],
            inMemory: true
        )
}
