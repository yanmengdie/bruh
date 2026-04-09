import SwiftUI
import SwiftData
import UIKit

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\MessageThread.lastMessageAt, order: .reverse)]) private var threads: [MessageThread]
    @Query(sort: [SortDescriptor(\ContentDelivery.sortDate, order: .reverse)]) private var deliveries: [ContentDelivery]
    @Query(sort: [SortDescriptor(\Contact.name, order: .forward)]) private var contacts: [Contact]
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @AppStorage("lastViewedFeedAt") private var lastViewedFeedAtInterval: Double = 0
    @AppStorage("lastViewedAlbumAt") private var lastViewedAlbumAtInterval: Double = 0

    @State private var homePath: [AppDestination] = []
    @State private var messageService = MessageService()

    var body: some View {
        Group {
            if hasCompletedOnboarding {
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
                            ContactsView()
                        case .imessage:
                            MessagesScreen(
                                threads: threads,
                                contacts: contacts,
                                service: messageService,
                                backgroundColor: messagesScreenBackground
                            )
                        case .feed:
                            FeedView()
                                .onAppear {
                                    lastViewedFeedAtInterval = Date().timeIntervalSince1970
                                }
                        case .album:
                            AlbumView()
                                .onAppear {
                                    lastViewedAlbumAtInterval = Date().timeIntervalSince1970
                                }
                        case .settings:
                            SettingsScreen()
                        }
                    }
                }
                .enableUnifiedSwipeBack()
                .task {
                    await bootstrapApp()
                }
                .onAppear(perform: configureNavigationAppearance)
            } else {
                Onboarding {
                    hasCompletedOnboarding = true
                }
            }
        }
    }

    private var totalUnreadMessages: Int {
        return max(0, acceptedPersonaIds.reduce(0) { count, personaId in
            let fallbackCount = threads.first(where: { $0.personaId == personaId })?.unreadCount ?? 0
            return count + MessageReadStateStore.unreadCount(
                for: personaId,
                deliveries: messageDeliveries,
                fallbackCount: fallbackCount
            )
        })
    }

    private var messagesScreenBackground: Color {
        AppTheme.messagesBackground
    }

    private var totalUnreadMoments: Int {
        guard lastViewedFeedAtInterval > 0 else { return feedDeliveries.count }
        let lastViewed = Date(timeIntervalSince1970: lastViewedFeedAtInterval)
        return feedDeliveries.reduce(0) { count, delivery in
            count + (delivery.sortDate > lastViewed ? 1 : 0)
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
        Set(
            contacts
                .filter { $0.relationshipStatusValue == .accepted }
                .compactMap(\.linkedPersonaId)
        )
    }

    private var feedDeliveries: [ContentDelivery] {
        deliveries.filter { delivery in
            delivery.channelValue == .feed
                && delivery.isVisible
                && acceptedPersonaIds.contains(delivery.personaId ?? "")
        }
    }

    private var messageDeliveries: [ContentDelivery] {
        deliveries.filter { delivery in
            delivery.channelValue == .message
                && delivery.isVisible
                && acceptedPersonaIds.contains(delivery.personaId ?? "")
        }
    }

    private var albumDeliveries: [ContentDelivery] {
        deliveries.filter { delivery in
            delivery.channelValue == .album
                && delivery.isVisible
                && !(delivery.imageUrl?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
                && acceptedPersonaIds.contains(delivery.personaId ?? "")
        }
    }

    private func handleHomeNavigation(_ destination: AppDestination) {
        homePath.append(destination)
    }

    @MainActor
    private func bootstrapApp() async {
        seedPersonas(into: modelContext)
        seedCurrentUserProfile(into: modelContext)
        seedSystemContacts(into: modelContext)
        try? messageService.prepareThreads(modelContext: modelContext)
        syncContentGraph(into: modelContext)
    }

    private func configureNavigationAppearance() {
        let backColor = UIColor(red: 0.52, green: 0.54, blue: 0.57, alpha: 1.0)
        UINavigationBar.appearance().tintColor = backColor
    }
}

private struct AlbumView: View {
    @Query(
        sort: [SortDescriptor(\ContentDelivery.sortDate, order: .reverse)],
        animation: .default
    ) private var deliveries: [ContentDelivery]
    @Query(sort: [SortDescriptor(\Contact.name, order: .forward)]) private var contacts: [Contact]
    @State private var selectedAsset: AlbumAssetSelection?

    private let gridColumns = [
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
    ]

    private var albumItems: [ContentDelivery] {
        deliveries.filter { delivery in
            delivery.channelValue == .album
                && delivery.isVisible
                && !(delivery.imageUrl?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
                && acceptedPersonaIds.contains(delivery.personaId ?? "")
        }
    }

    private var acceptedPersonaIds: Set<String> {
        Set(
            contacts
                .filter { $0.relationshipStatusValue == .accepted }
                .compactMap(\.linkedPersonaId)
        )
    }

    private var sections: [AlbumSection] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)
        let grouped = Dictionary(grouping: albumItems) { item in
            calendar.startOfDay(for: item.sortDate)
        }

        return grouped.keys
            .sorted(by: >)
            .compactMap { day in
                guard let items = grouped[day]?.sorted(by: { $0.sortDate > $1.sortDate }), !items.isEmpty else {
                    return nil
                }

                let title: String
                if day == today {
                    title = "Today"
                } else if day == yesterday {
                    title = "Yesterday"
                } else {
                    let formatter = DateFormatter()
                    formatter.dateFormat = "MMM d"
                    title = formatter.string(from: day)
                }

                let subtitle = "\(items.count) photos"
                return AlbumSection(id: day.formatted(date: .numeric, time: .omitted), title: title, subtitle: subtitle, items: items)
            }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                topBar
                    .padding(.top, 8)

                if sections.isEmpty {
                    albumEmptyState
                        .padding(.top, 18)
                } else {
                    ForEach(sections) { section in
                        VStack(alignment: .leading, spacing: 10) {
                            sectionTitle(
                                title: section.title,
                                subtitle: section.subtitle
                            )

                            LazyVGrid(columns: gridColumns, spacing: 2) {
                                ForEach(section.items) { item in
                                    albumTile(for: item)
                                }
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 28)
        }
        .scrollIndicators(.hidden)
        .background(AppTheme.messagesBackground)
        .navigationTitle("")
        .fullScreenCover(item: $selectedAsset) { asset in
            AlbumPreviewView(asset: asset)
        }
    }

    private var topBar: some View {
        HStack(alignment: .center) {
            Text("ALBUM")
                .font(.system(size: 24, weight: .black, design: .rounded))
                .foregroundStyle(Color.black.opacity(0.9))

            Spacer()
        }
    }

    private func sectionTitle(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 40, weight: .bold))
                .foregroundStyle(Color.black.opacity(0.88))

            Text(subtitle)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.black.opacity(0.32))
        }
    }

    private var albumEmptyState: some View {
        VStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.white.opacity(0.7))
                .frame(height: 240)
                .overlay {
                    VStack(spacing: 10) {
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.system(size: 34))
                            .foregroundStyle(.secondary)
                        Text("No Album Yet")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(Color.black.opacity(0.84))
                    }
                }
        }
    }

    private func albumTile(for item: ContentDelivery) -> some View {
        Button {
            guard let imageURLString = item.imageUrl,
                  let url = URL(string: imageURLString) else {
                return
            }
            selectedAsset = AlbumAssetSelection(
                id: item.id,
                url: url,
                caption: item.previewText,
                createdAt: item.sortDate
            )
        } label: {
            ZStack(alignment: .bottomLeading) {
                AsyncImage(url: URL(string: item.imageUrl ?? "")) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure:
                        RoundedRectangle(cornerRadius: 0, style: .continuous)
                            .fill(Color.black.opacity(0.06))
                            .overlay {
                                Image(systemName: "photo")
                                    .font(.system(size: 22))
                                    .foregroundStyle(.secondary)
                            }
                    case .empty:
                        RoundedRectangle(cornerRadius: 0, style: .continuous)
                            .fill(Color.black.opacity(0.04))
                            .overlay {
                                ProgressView()
                            }
                    @unknown default:
                        Color.black.opacity(0.04)
                    }
                }

                LinearGradient(
                    colors: [.clear, .black.opacity(0.28)],
                    startPoint: .top,
                    endPoint: .bottom
                )

                Text(relativeAlbumTime(item.sortDate))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.94))
                    .padding(8)
            }
            .frame(maxWidth: .infinity)
            .aspectRatio(1, contentMode: .fit)
            .clipped()
        }
        .buttonStyle(.plain)
    }

    private func relativeAlbumTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}

private struct AlbumSection: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let items: [ContentDelivery]
}

private struct AlbumAssetSelection: Identifiable {
    let id: String
    let url: URL
    let caption: String
    let createdAt: Date
}

private struct AlbumPreviewView: View {
    @Environment(\.dismiss) private var dismiss
    let asset: AlbumAssetSelection

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()

            AsyncImage(url: asset.url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.black)
                case .failure:
                    ContentUnavailableView("图片加载失败", systemImage: "photo")
                        .foregroundStyle(.white)
                case .empty:
                    ProgressView()
                        .tint(.white)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                @unknown default:
                    EmptyView()
                }
            }

            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(.white.opacity(0.92))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 18)
                .padding(.top, 18)

                Spacer()

                VStack(alignment: .leading, spacing: 6) {
                    if !asset.caption.isEmpty {
                        Text(asset.caption)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.white)
                            .lineLimit(3)
                    }

                    Text(asset.createdAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.72))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 18)
                .padding(.bottom, 28)
            }
        }
    }
}

private struct SettingsScreen: View {
    var body: some View {
        List {
            Label("通知设置", systemImage: "bell.badge")
            Label("内容偏好", systemImage: "slider.horizontal.3")
            Label("关于 Bruh", systemImage: "info.circle")
        }
        .navigationTitle("设置")
    }
}

private struct ContactDraft {
    var name: String = ""
    var phoneNumber: String = ""
    var email: String = ""
    var isFavorite: Bool = false
}

private struct ContactsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\Contact.name, order: .forward)]) private var contacts: [Contact]
    @Query(sort: [SortDescriptor(\Persona.inviteOrder, order: .forward)]) private var personas: [Persona]
    @Query private var profiles: [UserProfile]

    @State private var searchText = ""
    @State private var isPresentingForm = false
    @State private var presentedInvitation: BruhInvitation?
    @State private var isPresentingAddBruh = false
    @State private var editingContact: Contact?
    @State private var draft = ContactDraft()
    @State private var validationError: String?
    @State private var activeIndexLetter: String?
    @State private var lastIndexFeedbackLetter: String?
    private static let alphabet: [String] = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ").map(String.init) + ["#"]

    private var currentProfile: UserProfile? {
        profiles.first(where: { $0.id == CurrentUserProfileStore.userId })
    }

    private var filteredContacts: [Contact] {
        let sorted = contacts
            .filter(\.isVisibleInContactsList)
            .sorted {
            if $0.isFavorite != $1.isFavorite { return $0.isFavorite && !$1.isFavorite }
            return sortKey(for: $0.name).localizedCaseInsensitiveCompare(sortKey(for: $1.name)) == .orderedAscending
        }

        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return sorted }

        return sorted.filter { contact in
            contact.name.localizedCaseInsensitiveContains(query)
                || contact.phoneNumber.localizedCaseInsensitiveContains(query)
                || contact.email.localizedCaseInsensitiveContains(query)
        }
    }

    private var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var sectionedContacts: [(key: String, values: [Contact])] {
        let grouped = Dictionary(grouping: filteredContacts, by: sectionKey)
        return Self.alphabet.compactMap { key in
            guard let values = grouped[key], !values.isEmpty else { return nil }
            return (key, values)
        }
    }

    private var pendingInvitations: [BruhInvitation] {
        contacts
            .filter(\.isPendingInvitation)
            .sorted { ($0.inviteOrder ?? 999) < ($1.inviteOrder ?? 999) }
            .compactMap { contact in
                guard let personaId = contact.linkedPersonaId,
                      let persona = personas.first(where: { $0.id == personaId }) else {
                    return nil
                }
                return BruhInvitation(persona: persona, contact: contact)
            }
    }

    private var pendingInvitationCount: Int {
        pendingInvitations.count
    }

    var body: some View {
        ScrollViewReader { proxy in
            ZStack(alignment: .trailing) {
                List {
                    if !isSearching {
                        topCards
                            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                    }

                    if filteredContacts.isEmpty {
                        ContentUnavailableView(
                            searchText.isEmpty ? "暂无联系人" : "无搜索结果",
                            systemImage: searchText.isEmpty ? "person.crop.circle.badge.plus" : "magnifyingglass",
                            description: Text(searchText.isEmpty ? "点进“新鸽们”接收新的好友请求。" : "试试其他姓名、手机号或邮箱。")
                        )
                        .frame(maxWidth: .infinity, alignment: .center)
                        .listRowBackground(Color.clear)
                    } else if isSearching {
                        ForEach(filteredContacts, id: \.id) { contact in
                            contactListRow(contact)
                        }
                    } else {
                        ForEach(sectionedContacts, id: \.key) { section in
                            Section {
                                ForEach(section.values, id: \.id) { contact in
                                    contactListRow(contact)
                                }
                            } header: {
                                Text(section.key)
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundStyle(Color.black.opacity(0.30))
                                    .id("section-\(section.key)")
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .listSectionSeparator(.hidden)
                .scrollContentBackground(.hidden)
                .scrollIndicators(.hidden)
                .background(AppTheme.messagesBackground)
                .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always))
                .navigationTitle("")

                if !isSearching && !sectionedContacts.isEmpty {
                    alphabetIndex(proxy: proxy)
                        .padding(.trailing, 0)
                        .padding(.top, 38)
                }
            }
        }
        .sheet(isPresented: $isPresentingForm) {
            NavigationStack {
                ContactFormView(
                    title: editingContact == nil ? "新建联系人" : "编辑联系人",
                    draft: $draft,
                    validationError: validationError,
                    onCancel: {
                        isPresentingForm = false
                    },
                    onSave: saveContact
                )
            }
        }
        .navigationDestination(item: $presentedInvitation) { invitation in
            NewBruhView(
                invitation: invitation,
                lockedCandidateNames: lockedCandidateNames(excluding: invitation.personaId),
                onAccept: acceptInvitation,
                onIgnore: ignoreInvitation
            )
        }
        .navigationDestination(isPresented: $isPresentingAddBruh) {
            AddBruhView()
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isPresentingAddBruh = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 22, weight: .regular))
                        .foregroundStyle(Color(red: 0.56, green: 0.57, blue: 0.58))
                }
                .buttonStyle(.plain)
            }
        }
        .task {
            seedPersonas(into: modelContext)
            seedCurrentUserProfile(into: modelContext)
            seedSystemContacts(into: modelContext)
            normalizeInviteFrontier()
        }
    }

    private var topCards: some View {
        VStack(spacing: 12) {
            profileCard
            quickActionsCard
        }
    }

    private var profileCard: some View {
        let rawProfileName = currentProfile?.displayName ?? "我"
        let profileName = rawProfileName == "You" ? "我" : rawProfileName
        let profileHandle = currentProfile?.bruhHandle ?? "@yourboi"

        return HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(red: 0.84, green: 0.81, blue: 0.73))
                .frame(width: 66, height: 66)
                .overlay {
                    Text("😎")
                        .font(.system(size: 35))
                }

            VStack(alignment: .leading, spacing: 4) {
                Text(profileName)
                    .font(.system(size: 21, weight: .bold))
                    .foregroundStyle(Color.black.opacity(0.86))
                Text("鸽们账号：\(profileHandle)")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.black.opacity(0.3))
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.black.opacity(0.18))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .background(Color.white.opacity(0.68))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var quickActionsCard: some View {
        VStack(spacing: 0) {
            quickActionRow(
                icon: "🤝",
                iconBackground: Color(red: 0.94, green: 0.84, blue: 0.84),
                title: "新鸽们",
                trailing: pendingInvitationCount > 0 ? AnyView(
                    Text("\(pendingInvitationCount)")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 30, height: 30)
                        .background(Color(red: 0.84, green: 0.15, blue: 0.24))
                        .clipShape(Circle())
                ) : AnyView(EmptyView()),
                action: openNewBruh
            )

            Divider().opacity(0.28)

            quickActionRow(
                icon: "👥",
                iconBackground: Color(red: 0.86, green: 0.87, blue: 0.88),
                title: "群聊",
                action: {}
            )

            Divider().opacity(0.28)

            quickActionRow(
                icon: "🏷️",
                iconBackground: Color(red: 0.84, green: 0.89, blue: 0.82),
                title: "标签",
                action: {}
            )
        }
        .background(Color.white.opacity(0.68))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func quickActionRow(
        icon: String,
        iconBackground: Color,
        title: String,
        trailing: AnyView = AnyView(EmptyView()),
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(iconBackground)
                    .frame(width: 44, height: 44)
                    .overlay {
                        Text(icon)
                            .font(.system(size: 20))
                    }

                Text(title)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Color.black.opacity(0.86))

                Spacer(minLength: 0)
                trailing
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func alphabetIndex(proxy: ScrollViewProxy) -> some View {
        HStack(spacing: 8) {
            if let activeIndexLetter {
                Text(activeIndexLetter)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Color(red: 0.30, green: 0.41, blue: 0.63))
                    .frame(width: 44, height: 44)
                    .background(Color.white.opacity(0.85))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .shadow(color: .black.opacity(0.08), radius: 6, y: 2)
            }

            GeometryReader { geo in
                VStack(spacing: 3) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.black.opacity(0.45))

                    ForEach(Self.alphabet, id: \.self) { letter in
                        Text(letter)
                            .font(.system(size: activeIndexLetter == letter ? 10 : 9, weight: .semibold))
                            .foregroundStyle(activeIndexLetter == letter ? Color(red: 0.22, green: 0.34, blue: 0.59) : Color(red: 0.30, green: 0.41, blue: 0.63))
                            .frame(width: 16, height: 12)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                jumpToIndexLetter(letter, proxy: proxy, animated: true)
                            }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let rowCount = CGFloat(Self.alphabet.count + 1)
                            let rowHeight = geo.size.height / max(rowCount, 1)
                            let raw = Int(floor(value.location.y / rowHeight)) - 1

                            guard raw >= 0, raw < Self.alphabet.count else {
                                activeIndexLetter = nil
                                return
                            }

                            let letter = Self.alphabet[raw]
                            jumpToIndexLetter(letter, proxy: proxy, animated: false)
                        }
                        .onEnded { _ in
                            activeIndexLetter = nil
                            lastIndexFeedbackLetter = nil
                        }
                )
            }
            .frame(width: 18)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 2)
        .background(Color.clear)
        .animation(.easeOut(duration: 0.12), value: activeIndexLetter)
    }

    private func sectionKey(for contact: Contact) -> String {
        guard let first = sortKey(for: contact.name).trimmingCharacters(in: .whitespacesAndNewlines).uppercased().first else {
            return "#"
        }
        let key = String(first)
        return Self.alphabet.contains(key) ? key : "#"
    }

    private func sortKey(for name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        let mutable = NSMutableString(string: trimmed) as CFMutableString
        CFStringTransform(mutable, nil, kCFStringTransformToLatin, false)
        CFStringTransform(mutable, nil, kCFStringTransformStripCombiningMarks, false)
        return (mutable as String).uppercased()
    }

    private func jumpToIndexLetter(_ letter: String, proxy: ScrollViewProxy, animated: Bool) {
        guard let target = targetSection(for: letter) else { return }
        activeIndexLetter = target

        if lastIndexFeedbackLetter != target {
            UISelectionFeedbackGenerator().selectionChanged()
            lastIndexFeedbackLetter = target
        }

        if animated {
            withAnimation(.easeInOut(duration: 0.18)) {
                proxy.scrollTo("section-\(target)", anchor: .top)
            }
        } else {
            proxy.scrollTo("section-\(target)", anchor: .top)
        }
    }

    private func targetSection(for letter: String) -> String? {
        let existing = Set(sectionedContacts.map(\.key))
        guard let requestedIndex = Self.alphabet.firstIndex(of: letter) else { return nil }

        if existing.contains(letter) {
            return letter
        }

        for index in requestedIndex..<Self.alphabet.count where existing.contains(Self.alphabet[index]) {
            return Self.alphabet[index]
        }

        for index in stride(from: requestedIndex - 1, through: 0, by: -1) where existing.contains(Self.alphabet[index]) {
            return Self.alphabet[index]
        }

        return nil
    }

    private func contactListRow(_ contact: Contact) -> some View {
        contactRow(contact)
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                Button("删除", role: .destructive) {
                    delete(contact)
                }

                Button("编辑") {
                    startEditing(contact)
                }
                .tint(.blue)
            }
            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                Button {
                    toggleFavorite(contact)
                } label: {
                    Image(systemName: contact.isFavorite ? "star.slash.fill" : "star.fill")
                }
                .tint(contact.isFavorite ? .gray : .orange)
            }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }

    private func contactRow(_ contact: Contact) -> some View {
        let themeColor = AppTheme.color(from: contact.themeColorHex, fallback: .blue)

        return HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(themeColor.opacity(contact.isFavorite ? 0.24 : 0.16))
                .frame(width: 44, height: 44)
                .overlay {
                    if !contact.avatarName.isEmpty, UIImage(named: contact.avatarName) != nil {
                        Image(contact.avatarName)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 44, height: 44)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    } else {
                        Text(String(contact.name.prefix(1)).uppercased())
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(themeColor)
                    }
                }

            VStack(alignment: .leading, spacing: 3) {
                Text(contact.name)
                    .font(.system(size: 16, weight: .medium))

                if !contact.locationLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(contact.locationLabel)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(Color.black.opacity(0.34))
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func startCreating() {
        editingContact = nil
        draft = ContactDraft()
        validationError = nil
        isPresentingForm = true
    }

    private func openNewBruh() {
        normalizeInviteFrontier()
        guard let invitation = pendingInvitations.first else { return }
        presentedInvitation = invitation
    }

    private func acceptInvitation(_ invitation: BruhInvitation) {
        guard let contact = contact(for: invitation.personaId) else { return }
        presentedInvitation = nil
        let wasAccepted = contact.relationshipStatusValue == .accepted

        contact.relationshipStatusValue = .accepted
        contact.acceptedAt = contact.acceptedAt ?? .now
        contact.ignoredAt = nil
        contact.isFavorite = true
        contact.updatedAt = .now

        normalizeInviteFrontier()

        if !wasAccepted && invitation.personaId == "trump" {
            scheduleTrumpFollowUps()
        }

        try? modelContext.save()
    }

    private func ignoreInvitation(_ invitation: BruhInvitation) {
        guard let contact = contact(for: invitation.personaId) else { return }
        presentedInvitation = nil
        contact.relationshipStatusValue = .ignored
        contact.ignoredAt = .now
        contact.isFavorite = false
        contact.updatedAt = .now
        normalizeInviteFrontier()
        try? modelContext.save()
    }

    private func startEditing(_ contact: Contact) {
        editingContact = contact
        draft = ContactDraft(
            name: contact.name,
            phoneNumber: contact.phoneNumber,
            email: contact.email,
            isFavorite: contact.isFavorite
        )
        validationError = nil
        isPresentingForm = true
    }

    private func saveContact() {
        let normalizedName = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedPhone = draft.phoneNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedEmail = draft.email.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalizedName.isEmpty else {
            validationError = "Name cannot be empty."
            return
        }

        guard !normalizedPhone.isEmpty else {
            validationError = "Phone number cannot be empty."
            return
        }

        if let editingContact {
            editingContact.name = normalizedName
            editingContact.phoneNumber = normalizedPhone
            editingContact.email = normalizedEmail
            editingContact.isFavorite = draft.isFavorite
            editingContact.relationshipStatusValue = .custom
            editingContact.updatedAt = .now
        } else {
            let contact = Contact(
                name: normalizedName,
                phoneNumber: normalizedPhone,
                email: normalizedEmail,
                isFavorite: draft.isFavorite,
                relationshipStatus: ContactRelationshipStatus.custom.rawValue
            )
            modelContext.insert(contact)
        }

        do {
            try modelContext.save()
            isPresentingForm = false
            validationError = nil
        } catch {
            validationError = error.localizedDescription
        }
    }

    private func delete(_ contact: Contact) {
        modelContext.delete(contact)
        try? modelContext.save()
    }

    private func toggleFavorite(_ contact: Contact) {
        contact.isFavorite.toggle()
        contact.updatedAt = .now
        try? modelContext.save()
    }

    private func normalizeInviteFrontier() {
        let personaContacts = contacts
            .filter { $0.linkedPersonaId != nil }
            .sorted { ($0.inviteOrder ?? 999) < ($1.inviteOrder ?? 999) }

        var frontierConsumed = false
        for contact in personaContacts {
            switch contact.relationshipStatusValue {
            case .accepted, .ignored:
                continue
            case .pending:
                if frontierConsumed {
                    contact.relationshipStatusValue = .locked
                    contact.updatedAt = .now
                } else {
                    frontierConsumed = true
                }
            case .locked:
                if !frontierConsumed {
                    contact.relationshipStatusValue = .pending
                    contact.updatedAt = .now
                    frontierConsumed = true
                }
            case .custom:
                continue
            }
        }

        if modelContext.hasChanges {
            try? modelContext.save()
        }
    }

    private func contact(for personaId: String) -> Contact? {
        contacts.first(where: { $0.linkedPersonaId == personaId })
    }

    private func lockedCandidateNames(excluding personaId: String) -> [String] {
        contacts
            .filter { $0.linkedPersonaId != nil && $0.relationshipStatusValue == .locked }
            .filter { $0.linkedPersonaId != personaId }
            .sorted { ($0.inviteOrder ?? 999) < ($1.inviteOrder ?? 999) }
            .map(\.name)
    }

    private func scheduleTrumpFollowUps() {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            insertIncomingMessage(
                personaId: "trump",
                text: "You’re in. Big moves ahead. I’ll send you the most important update first.",
                sourcePostIds: []
            )

            try? await Task.sleep(nanoseconds: 6_000_000_000)
            insertIncomingMessage(
                personaId: "trump",
                text: "https://www.reuters.com/world/asia-pacific/trump-agrees-two-week-ceasefire-iran-says-safe-passage-through-hormuz-possible-2026-04-08/",
                sourcePostIds: ["trump-news-1"]
            )
        }
    }

    private func insertIncomingMessage(personaId: String, text: String, sourcePostIds: [String]) {
        let thread = ensureThread(for: personaId)
        let now = Date()
        let message = PersonaMessage(
            id: UUID().uuidString,
            threadId: thread.id,
            personaId: personaId,
            text: text,
            isIncoming: true,
            createdAt: now,
            deliveryState: "sent",
            sourcePostIds: sourcePostIds,
            isSeedMessage: false
        )
        modelContext.insert(message)
        ContentGraphStore.syncIncomingMessage(message, in: modelContext)
        thread.lastMessagePreview = text
        thread.lastMessageAt = now
        thread.unreadCount = max(thread.unreadCount, 0) + 1
        thread.updatedAt = now
        try? modelContext.save()
    }

    private func ensureThread(for personaId: String) -> MessageThread {
        var descriptor = FetchDescriptor<MessageThread>(
            predicate: #Predicate { $0.id == personaId }
        )
        descriptor.fetchLimit = 1

        if let existing = try? modelContext.fetch(descriptor).first {
            return existing
        }

        let thread = MessageThread(
            id: personaId,
            personaId: personaId,
            lastMessagePreview: "",
            lastMessageAt: .distantPast,
            unreadCount: 0
        )
        modelContext.insert(thread)
        return thread
    }
}

private struct ContactFormView: View {
    let title: String
    @Binding var draft: ContactDraft
    let validationError: String?
    let onCancel: () -> Void
    let onSave: () -> Void

    var body: some View {
        Form {
            Section("Basic Info") {
                TextField("Name", text: $draft.name)
                    .textInputAutocapitalization(.words)

                TextField("Phone Number", text: $draft.phoneNumber)
                    .keyboardType(.phonePad)

                TextField("Email", text: $draft.email)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.emailAddress)
                    .autocorrectionDisabled(true)
            }

            Section("Options") {
                Toggle("Favorite Contact", isOn: $draft.isFavorite)
            }

            if let validationError {
                Section {
                    Text(validationError)
                        .foregroundStyle(.red)
                        .font(.system(size: 13))
                }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Cancel", action: onCancel)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Save", action: onSave)
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
                ContentEvent.self,
                ContentDelivery.self,
                MessageThread.self,
                PersonaMessage.self,
                FeedComment.self,
                FeedLike.self,
                Contact.self,
                UserProfile.self,
            ],
            inMemory: true
        )
}
