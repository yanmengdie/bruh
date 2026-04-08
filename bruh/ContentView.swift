import SwiftUI
import SwiftData
import UIKit

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\MessageThread.lastMessageAt, order: .reverse)]) private var threads: [MessageThread]
    @Query(sort: [SortDescriptor(\PersonaPost.publishedAt, order: .reverse)]) private var posts: [PersonaPost]
    @Query(sort: [SortDescriptor(\Contact.name, order: .forward)]) private var contacts: [Contact]
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @AppStorage("hasOpenedAlbum") private var hasOpenedAlbum = false
    @AppStorage("lastViewedFeedAt") private var lastViewedFeedAtInterval: Double = 0

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
                        hasNewAlbumBadge: !hasOpenedAlbum
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
                                    hasOpenedAlbum = true
                                }
                        case .settings:
                            SettingsScreen()
                        }
                    }
                }
                .enableUnifiedSwipeBack()
                .task {
                    try? await messageService.ensureThreadsExist(modelContext: modelContext, userInterests: InterestPreferences.selectedInterests())
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
        max(0, threads.reduce(0) { $0 + max(0, $1.unreadCount) })
    }

    private var messagesScreenBackground: Color {
        AppTheme.messagesBackground
    }

    private var totalUnreadMoments: Int {
        guard lastViewedFeedAtInterval > 0 else { return posts.count }
        let lastViewed = Date(timeIntervalSince1970: lastViewedFeedAtInterval)
        return posts.reduce(0) { count, post in
            count + (post.publishedAt > lastViewed ? 1 : 0)
        }
    }

    private func handleHomeNavigation(_ destination: AppDestination) {
        homePath.append(destination)
    }

    private func configureNavigationAppearance() {
        let backColor = UIColor(red: 0.52, green: 0.54, blue: 0.57, alpha: 1.0)
        UINavigationBar.appearance().tintColor = backColor
    }
}

private struct AlbumView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                topBar
                    .padding(.top, 8)

                sectionTitle(
                    title: "最近",
                    subtitle: "今天 - 128 张照片和视频"
                )

                recentsMosaic
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                sectionTitle(
                    title: "昨天",
                    subtitle: "4 月 7 日 - 84 张照片和视频"
                )
                .padding(.top, 6)

                HStack(spacing: 2) {
                    Color(red: 0.12, green: 0.70, blue: 0.52)
                    Color(red: 0.82, green: 0.18, blue: 0.26)
                    Color(red: 0.90, green: 0.34, blue: 0.62)
                }
                .frame(height: 6)
                .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 28)
        }
        .scrollIndicators(.hidden)
        .background(AppTheme.messagesBackground)
        .navigationTitle("")
    }

    private var topBar: some View {
        HStack(alignment: .center) {
            Text("相册")
                .font(.system(size: 24, weight: .black, design: .rounded))
                .foregroundStyle(Color.black.opacity(0.9))

            Spacer()

            CircleButton(symbol: "plus")
            CircleButton(symbol: "ellipsis")
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

    private var recentsMosaic: some View {
        VStack(spacing: 2) {
            HStack(spacing: 2) {
                tile(Color(red: 0.80, green: 0.08, blue: 0.15), height: 194)
                VStack(spacing: 2) {
                    tile(Color(red: 0.20, green: 0.29, blue: 0.52), height: 96)
                    tile(Color(red: 0.86, green: 0.66, blue: 0.12), height: 96)
                }
            }

            HStack(spacing: 2) {
                tile(Color(red: 0.16, green: 0.55, blue: 0.34), height: 96)
                tile(Color(red: 0.24, green: 0.52, blue: 0.86), height: 96)
                tile(Color(red: 0.96, green: 0.44, blue: 0.12), height: 96)
            }

            HStack(spacing: 2) {
                tile(Color(red: 0.43, green: 0.71, blue: 0.86), height: 96)
                tile(Color(red: 0.95, green: 0.52, blue: 0.18), height: 96)
                tile(Color(red: 0.36, green: 0.32, blue: 0.85), height: 96)
            }
        }
    }

    private func tile(_ color: Color, height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 0, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [color.opacity(0.95), color.opacity(0.78)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(maxWidth: .infinity)
            .frame(height: height)
    }
}

private struct CircleButton: View {
    let symbol: String

    var body: some View {
        Button {} label: {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(Color.black.opacity(0.58))
                .frame(width: 56, height: 56)
                .background(Color.white.opacity(0.45))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
    }
}

private struct SettingsScreen: View {
    var body: some View {
        List {
            Label("通知设置", systemImage: "bell.badge")
            Label("内容偏好", systemImage: "slider.horizontal.3")
            Label("关于鸽们", systemImage: "info.circle")
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

    @State private var searchText = ""
    @State private var isPresentingForm = false
    @State private var presentedInvitation: BruhInvitation?
    @State private var isPresentingAddBruh = false
    @State private var editingContact: Contact?
    @State private var draft = ContactDraft()
    @State private var validationError: String?
    @State private var activeIndexLetter: String?
    @State private var lastIndexFeedbackLetter: String?
    @AppStorage("invite_flow_initialized") private var inviteFlowInitialized = false
    @AppStorage("invite_trump_accepted") private var inviteTrumpAccepted = false
    @AppStorage("invite_musk_unlocked") private var inviteMuskUnlocked = false
    @AppStorage("invite_musk_accepted") private var inviteMuskAccepted = false
    @AppStorage("invite_musk_ignored") private var inviteMuskIgnored = false
    @AppStorage("invite_zuckerberg_unlocked") private var inviteZuckerbergUnlocked = false
    @AppStorage("invite_zuckerberg_accepted") private var inviteZuckerbergAccepted = false
    @AppStorage("invite_zuckerberg_ignored") private var inviteZuckerbergIgnored = false
    @AppStorage("invite_trump_ignored") private var inviteTrumpIgnored = false
    @AppStorage("invite_justin_sun_unlocked") private var inviteJustinSunUnlocked = false
    @AppStorage("invite_justin_sun_accepted") private var inviteJustinSunAccepted = false
    @AppStorage("invite_justin_sun_ignored") private var inviteJustinSunIgnored = false
    @AppStorage("invite_papi_unlocked") private var invitePapiUnlocked = false
    @AppStorage("invite_papi_accepted") private var invitePapiAccepted = false
    @AppStorage("invite_papi_ignored") private var invitePapiIgnored = false
    @AppStorage("invite_sam_altman_unlocked") private var inviteSamAltmanUnlocked = false
    @AppStorage("invite_sam_altman_accepted") private var inviteSamAltmanAccepted = false
    @AppStorage("invite_sam_altman_ignored") private var inviteSamAltmanIgnored = false
    @AppStorage("invite_lei_jun_unlocked") private var inviteLeiJunUnlocked = false
    @AppStorage("invite_lei_jun_accepted") private var inviteLeiJunAccepted = false
    @AppStorage("invite_lei_jun_ignored") private var inviteLeiJunIgnored = false
    @AppStorage("invite_sun_yuchen_unlocked") private var inviteSunYuchenUnlocked = false
    @AppStorage("invite_sun_yuchen_accepted") private var inviteSunYuchenAccepted = false
    @AppStorage("invite_sun_yuchen_ignored") private var inviteSunYuchenIgnored = false
    @AppStorage("invite_liu_jingkang_unlocked") private var inviteLiuJingkangUnlocked = false
    @AppStorage("invite_liu_jingkang_accepted") private var inviteLiuJingkangAccepted = false
    @AppStorage("invite_liu_jingkang_ignored") private var inviteLiuJingkangIgnored = false
    @AppStorage("invite_kim_kardashian_unlocked") private var inviteKimUnlocked = false
    @AppStorage("invite_kim_kardashian_accepted") private var inviteKimAccepted = false
    @AppStorage("invite_kim_kardashian_ignored") private var inviteKimIgnored = false
    @AppStorage("invite_luo_yonghao_unlocked") private var inviteLuoYonghaoUnlocked = false
    @AppStorage("invite_luo_yonghao_accepted") private var inviteLuoYonghaoAccepted = false
    @AppStorage("invite_luo_yonghao_ignored") private var inviteLuoYonghaoIgnored = false
    private static let alphabet: [String] = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ").map(String.init) + ["#"]

    private var filteredContacts: [Contact] {
        let sorted = contacts.sorted {
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
        var items: [BruhInvitation] = []
        if !inviteTrumpAccepted, !inviteTrumpIgnored { items.append(.trump) }
        if inviteMuskUnlocked, !inviteMuskAccepted, !inviteMuskIgnored { items.append(.musk) }
        if inviteJustinSunUnlocked, !inviteJustinSunAccepted, !inviteJustinSunIgnored { items.append(.justinSun) }
        if invitePapiUnlocked, !invitePapiAccepted, !invitePapiIgnored { items.append(.papi) }
        if inviteSamAltmanUnlocked, !inviteSamAltmanAccepted, !inviteSamAltmanIgnored { items.append(.samAltman) }
        if inviteLeiJunUnlocked, !inviteLeiJunAccepted, !inviteLeiJunIgnored { items.append(.leiJun) }
        if inviteSunYuchenUnlocked, !inviteSunYuchenAccepted, !inviteSunYuchenIgnored { items.append(.sunYuchen) }
        if inviteLiuJingkangUnlocked, !inviteLiuJingkangAccepted, !inviteLiuJingkangIgnored { items.append(.liuJingkang) }
        if inviteKimUnlocked, !inviteKimAccepted, !inviteKimIgnored { items.append(.kimKardashian) }
        if inviteLuoYonghaoUnlocked, !inviteLuoYonghaoAccepted, !inviteLuoYonghaoIgnored { items.append(.luoYonghao) }
        return items
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
                            searchText.isEmpty ? "暂无鸽们" : "无搜索结果",
                            systemImage: searchText.isEmpty ? "person.crop.circle.badge.plus" : "magnifyingglass",
                            description: Text(searchText.isEmpty ? "点击“新鸽们”添加第一个鸽们。" : "试试其他姓名、手机号或邮箱。")
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
                    title: editingContact == nil ? "新建鸽们" : "编辑鸽们",
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
            bootstrapInviteFlowIfNeeded()
            restoreInviteFlowIfNeeded()
            ensureInvitationProgressConsistency()
            normalizeInvitationContactsIfNeeded()
        }
    }

    private var topCards: some View {
        VStack(spacing: 12) {
            profileCard
            quickActionsCard
        }
    }

    private var profileCard: some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(red: 0.84, green: 0.81, blue: 0.73))
                .frame(width: 66, height: 66)
                .overlay {
                    Text("😎")
                        .font(.system(size: 35))
                }

            VStack(alignment: .leading, spacing: 4) {
                Text("我")
                    .font(.system(size: 21, weight: .bold))
                    .foregroundStyle(Color.black.opacity(0.86))
                Text("鸽们账号：@yourboi")
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
        let key = sectionKey(for: contact.name)
        return Self.alphabet.contains(key) ? key : "#"
    }

    private func sectionKey(for name: String) -> String {
        guard let first = sortKey(for: name).trimmingCharacters(in: .whitespacesAndNewlines).uppercased().first else {
            return "#"
        }

        let letter = String(first)
        return Self.alphabet.contains(letter) ? letter : "#"
    }

    private func sortKey(for name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        // Convert Chinese to pinyin (and keep Latin as-is) for consistent A-Z sectioning.
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
                    if UIImage(named: contact.avatarName) != nil {
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
        ensureInvitationProgressConsistency()
        recoverPendingInvitationsIfNeeded()
        if pendingInvitations.isEmpty {
            // Only restart the whole flow when nothing has been decided yet.
            // Otherwise, an "empty pending list" usually means the user has ignored/accepted
            // all currently available invitations.
            let hasDecidedAnyInvitation =
                inviteTrumpAccepted || inviteTrumpIgnored
                || inviteMuskAccepted || inviteMuskIgnored
                || inviteZuckerbergAccepted || inviteZuckerbergIgnored
                || inviteJustinSunAccepted || inviteJustinSunIgnored
                || invitePapiAccepted || invitePapiIgnored
                || inviteSamAltmanAccepted || inviteSamAltmanIgnored
                || inviteLeiJunAccepted || inviteLeiJunIgnored
                || inviteSunYuchenAccepted || inviteSunYuchenIgnored
                || inviteLiuJingkangAccepted || inviteLiuJingkangIgnored
                || inviteKimAccepted || inviteKimIgnored
                || inviteLuoYonghaoAccepted || inviteLuoYonghaoIgnored

            if !hasDecidedAnyInvitation {
                forceRestartInvitationFlow()
            } else {
                return
            }
        }
        guard let invitation = pendingInvitations.first else { return }
        presentedInvitation = invitation
    }

    private func acceptInvitation(_ invitation: BruhInvitation) {
        addContactIfNeeded(for: invitation)
        presentedInvitation = nil

        switch invitation.personaId {
        case "trump":
            inviteTrumpAccepted = true
            inviteTrumpIgnored = false
            scheduleTrumpFollowUps()
        case "musk":
            inviteMuskAccepted = true
            inviteMuskIgnored = false
            inviteZuckerbergUnlocked = true
        case "zuckerberg":
            inviteZuckerbergAccepted = true
            inviteZuckerbergIgnored = false
            inviteJustinSunUnlocked = true
        case "justin_sun":
            inviteJustinSunAccepted = true
            inviteJustinSunIgnored = false
            scheduleJustinSunFollowUps()
            unlockAdditionalInvitations()
        default:
            acceptAdditionalInvitation(personaId: invitation.personaId)
            break
        }
        ensureInvitationProgressConsistency()
        try? modelContext.save()
    }

    private func ignoreInvitation(_ invitation: BruhInvitation) {
        presentedInvitation = nil
        switch invitation.personaId {
        case "trump":
            inviteTrumpIgnored = true
            inviteMuskUnlocked = true
        case "musk":
            inviteMuskIgnored = true
            inviteZuckerbergUnlocked = true
        case "zuckerberg":
            inviteZuckerbergIgnored = true
            inviteJustinSunUnlocked = true
        case "justin_sun":
            inviteJustinSunIgnored = true
        default:
            ignoreAdditionalInvitation(personaId: invitation.personaId)
            break
        }
        ensureInvitationProgressConsistency()
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
            validationError = "姓名不能为空。"
            return
        }

        guard !normalizedPhone.isEmpty else {
            validationError = "手机号不能为空。"
            return
        }

        if let editingContact {
            editingContact.name = normalizedName
            editingContact.phoneNumber = normalizedPhone
            editingContact.email = normalizedEmail
            editingContact.isFavorite = draft.isFavorite
            editingContact.updatedAt = .now
        } else {
            let contact = Contact(
                name: normalizedName,
                phoneNumber: normalizedPhone,
                email: normalizedEmail,
                isFavorite: draft.isFavorite
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

    private func bootstrapInviteFlowIfNeeded() {
        guard !inviteFlowInitialized else { return }

        let existingContacts: [Contact] = (try? modelContext.fetch(FetchDescriptor<Contact>())) ?? []
        for contact in existingContacts {
            modelContext.delete(contact)
        }

        let existingThreads: [MessageThread] = (try? modelContext.fetch(FetchDescriptor<MessageThread>())) ?? []
        for thread in existingThreads {
            modelContext.delete(thread)
        }

        let existingMessages: [PersonaMessage] = (try? modelContext.fetch(FetchDescriptor<PersonaMessage>())) ?? []
        for message in existingMessages {
            modelContext.delete(message)
        }

        inviteTrumpAccepted = false
        inviteMuskUnlocked = true
        inviteMuskAccepted = false
        inviteMuskIgnored = false
        inviteZuckerbergUnlocked = false
        inviteZuckerbergAccepted = false
        inviteZuckerbergIgnored = false
        inviteJustinSunUnlocked = false
        inviteJustinSunAccepted = false
        inviteJustinSunIgnored = false
        invitePapiUnlocked = true
        invitePapiAccepted = false
        invitePapiIgnored = false
        inviteSamAltmanUnlocked = true
        inviteSamAltmanAccepted = false
        inviteSamAltmanIgnored = false
        inviteLeiJunUnlocked = true
        inviteLeiJunAccepted = false
        inviteLeiJunIgnored = false
        inviteSunYuchenUnlocked = true
        inviteSunYuchenAccepted = false
        inviteSunYuchenIgnored = false
        inviteLiuJingkangUnlocked = true
        inviteLiuJingkangAccepted = false
        inviteLiuJingkangIgnored = false
        inviteKimUnlocked = true
        inviteKimAccepted = false
        inviteKimIgnored = false
        inviteLuoYonghaoUnlocked = true
        inviteLuoYonghaoAccepted = false
        inviteLuoYonghaoIgnored = false
        inviteTrumpIgnored = false
        inviteFlowInitialized = true
        try? modelContext.save()
    }

    private func restoreInviteFlowIfNeeded() {
        let hasDecidedAnyInvitation =
            inviteTrumpAccepted || inviteTrumpIgnored
            || inviteMuskUnlocked || inviteMuskAccepted || inviteMuskIgnored
            || inviteZuckerbergUnlocked || inviteZuckerbergAccepted || inviteZuckerbergIgnored
            || inviteJustinSunUnlocked || inviteJustinSunAccepted || inviteJustinSunIgnored
            || invitePapiUnlocked || invitePapiAccepted || invitePapiIgnored
            || inviteSamAltmanUnlocked || inviteSamAltmanAccepted || inviteSamAltmanIgnored
            || inviteLeiJunUnlocked || inviteLeiJunAccepted || inviteLeiJunIgnored
            || inviteSunYuchenUnlocked || inviteSunYuchenAccepted || inviteSunYuchenIgnored
            || inviteLiuJingkangUnlocked || inviteLiuJingkangAccepted || inviteLiuJingkangIgnored
            || inviteKimUnlocked || inviteKimAccepted || inviteKimIgnored
            || inviteLuoYonghaoUnlocked || inviteLuoYonghaoAccepted || inviteLuoYonghaoIgnored

        guard contacts.isEmpty, pendingInvitations.isEmpty, !hasDecidedAnyInvitation else { return }

        inviteTrumpAccepted = false
        inviteMuskUnlocked = true
        inviteMuskAccepted = false
        inviteMuskIgnored = false
        inviteZuckerbergUnlocked = false
        inviteZuckerbergAccepted = false
        inviteZuckerbergIgnored = false
        inviteJustinSunUnlocked = false
        inviteJustinSunAccepted = false
        inviteJustinSunIgnored = false
        invitePapiUnlocked = true
        invitePapiAccepted = false
        invitePapiIgnored = false
        inviteSamAltmanUnlocked = true
        inviteSamAltmanAccepted = false
        inviteSamAltmanIgnored = false
        inviteLeiJunUnlocked = true
        inviteLeiJunAccepted = false
        inviteLeiJunIgnored = false
        inviteSunYuchenUnlocked = true
        inviteSunYuchenAccepted = false
        inviteSunYuchenIgnored = false
        inviteLiuJingkangUnlocked = true
        inviteLiuJingkangAccepted = false
        inviteLiuJingkangIgnored = false
        inviteKimUnlocked = true
        inviteKimAccepted = false
        inviteKimIgnored = false
        inviteLuoYonghaoUnlocked = true
        inviteLuoYonghaoAccepted = false
        inviteLuoYonghaoIgnored = false
        inviteTrumpIgnored = false
    }

    private func ensureInvitationProgressConsistency() {
        inviteMuskUnlocked = true
        invitePapiUnlocked = true
        inviteSamAltmanUnlocked = true
        inviteLeiJunUnlocked = true
        inviteSunYuchenUnlocked = true
        inviteLiuJingkangUnlocked = true
        inviteKimUnlocked = true
        inviteLuoYonghaoUnlocked = true

        if (inviteTrumpAccepted || inviteTrumpIgnored) && !inviteMuskAccepted && !inviteMuskIgnored {
            inviteMuskUnlocked = true
        }

        if (inviteMuskAccepted || inviteMuskIgnored) && !inviteZuckerbergAccepted && !inviteZuckerbergIgnored {
            inviteZuckerbergUnlocked = true
        }

        if (inviteZuckerbergAccepted || inviteZuckerbergIgnored) && !inviteJustinSunAccepted && !inviteJustinSunIgnored {
            inviteJustinSunUnlocked = true
        }

        if inviteJustinSunAccepted {
            unlockAdditionalInvitations()
        }
    }

    private func recoverPendingInvitationsIfNeeded() {
        guard pendingInvitations.isEmpty else { return }

        if !(inviteTrumpAccepted || inviteTrumpIgnored) {
            inviteTrumpIgnored = false
            inviteMuskUnlocked = true
            inviteMuskIgnored = false
            inviteZuckerbergUnlocked = false
            inviteZuckerbergIgnored = false
            inviteJustinSunUnlocked = false
            inviteJustinSunIgnored = false
            return
        }

        if !(inviteMuskAccepted || inviteMuskIgnored) {
            inviteMuskUnlocked = true
            inviteMuskIgnored = false
            return
        }

        if !(inviteZuckerbergAccepted || inviteZuckerbergIgnored) {
            inviteZuckerbergUnlocked = true
            inviteZuckerbergIgnored = false
            inviteJustinSunUnlocked = false
            inviteJustinSunIgnored = false
            return
        }

        if !(inviteJustinSunAccepted || inviteJustinSunIgnored) {
            inviteJustinSunUnlocked = true
            inviteJustinSunIgnored = false
            return
        }

        unlockAdditionalInvitations()
    }

    private func forceRestartInvitationFlow() {
        inviteTrumpAccepted = false
        inviteTrumpIgnored = false
        inviteMuskUnlocked = true
        inviteMuskAccepted = false
        inviteMuskIgnored = false
        inviteZuckerbergUnlocked = false
        inviteZuckerbergAccepted = false
        inviteZuckerbergIgnored = false
        inviteJustinSunUnlocked = false
        inviteJustinSunAccepted = false
        inviteJustinSunIgnored = false
        invitePapiUnlocked = true
        invitePapiAccepted = false
        invitePapiIgnored = false
        inviteSamAltmanUnlocked = true
        inviteSamAltmanAccepted = false
        inviteSamAltmanIgnored = false
        inviteLeiJunUnlocked = true
        inviteLeiJunAccepted = false
        inviteLeiJunIgnored = false
        inviteSunYuchenUnlocked = true
        inviteSunYuchenAccepted = false
        inviteSunYuchenIgnored = false
        inviteLiuJingkangUnlocked = true
        inviteLiuJingkangAccepted = false
        inviteLiuJingkangIgnored = false
        inviteKimUnlocked = true
        inviteKimAccepted = false
        inviteKimIgnored = false
        inviteLuoYonghaoUnlocked = true
        inviteLuoYonghaoAccepted = false
        inviteLuoYonghaoIgnored = false
    }

    private func addContactIfNeeded(for invitation: BruhInvitation) {
        if let existing = contacts.first(where: { contact in
            contact.linkedPersonaId == invitation.personaId
                || contact.name.localizedCaseInsensitiveCompare(invitation.displayName) == .orderedSame
        }) {
            if existing.linkedPersonaId == nil {
                existing.linkedPersonaId = invitation.personaId
            }
            existing.name = invitation.displayName
            existing.phoneNumber = invitation.phoneNumber
            existing.email = invitation.email
            existing.avatarName = invitation.avatarName
            existing.themeColorHex = invitation.themeHex
            existing.locationLabel = invitation.location
            existing.updatedAt = .now
            try? modelContext.save()
            return
        }

        let contact = Contact(
            linkedPersonaId: invitation.personaId,
            name: invitation.displayName,
            phoneNumber: invitation.phoneNumber,
            email: invitation.email,
            avatarName: invitation.avatarName,
            themeColorHex: invitation.themeHex,
            locationLabel: invitation.location,
            isFavorite: false
        )
        modelContext.insert(contact)
    }

    private func unlockAdditionalInvitations() {
        invitePapiUnlocked = true
        inviteSamAltmanUnlocked = true
        inviteLeiJunUnlocked = true
        inviteSunYuchenUnlocked = true
        inviteLiuJingkangUnlocked = true
        inviteKimUnlocked = true
        inviteLuoYonghaoUnlocked = true
    }

    private func acceptAdditionalInvitation(personaId: String) {
        switch personaId {
        case "papi":
            invitePapiAccepted = true
            invitePapiIgnored = false
            scheduleAdditionalPersonaFollowUps(personaId: "papi")
        case "sam_altman":
            inviteSamAltmanAccepted = true
            inviteSamAltmanIgnored = false
            scheduleAdditionalPersonaFollowUps(personaId: "sam_altman")
        case "lei_jun":
            inviteLeiJunAccepted = true
            inviteLeiJunIgnored = false
            scheduleAdditionalPersonaFollowUps(personaId: "lei_jun")
        case "sun_yuchen":
            inviteSunYuchenAccepted = true
            inviteSunYuchenIgnored = false
            scheduleAdditionalPersonaFollowUps(personaId: "sun_yuchen")
        case "liu_jingkang":
            inviteLiuJingkangAccepted = true
            inviteLiuJingkangIgnored = false
            scheduleAdditionalPersonaFollowUps(personaId: "liu_jingkang")
        case "kim_kardashian":
            inviteKimAccepted = true
            inviteKimIgnored = false
            scheduleAdditionalPersonaFollowUps(personaId: "kim_kardashian")
        case "luo_yonghao":
            inviteLuoYonghaoAccepted = true
            inviteLuoYonghaoIgnored = false
            scheduleAdditionalPersonaFollowUps(personaId: "luo_yonghao")
        default:
            break
        }
    }

    private func ignoreAdditionalInvitation(personaId: String) {
        switch personaId {
        case "papi":
            invitePapiIgnored = true
        case "sam_altman":
            inviteSamAltmanIgnored = true
        case "lei_jun":
            inviteLeiJunIgnored = true
        case "sun_yuchen":
            inviteSunYuchenIgnored = true
        case "liu_jingkang":
            inviteLiuJingkangIgnored = true
        case "kim_kardashian":
            inviteKimIgnored = true
        case "luo_yonghao":
            inviteLuoYonghaoIgnored = true
        default:
            break
        }
    }

    private func scheduleAdditionalPersonaFollowUps(personaId: String) {
        Task { @MainActor in
            let script: [(delaySeconds: UInt64, text: String)] = {
                switch personaId {
                case "musk":
                    return [(2, "Saw your add. X is a real-time sensor for the world now. I’ll forward the signals. ⚡️")]
                case "papi":
                    return [(2, "在吗 bro？今天有个热梗我看一眼就知道要爆。"), (6, "我只发你真正有梗的，其他都是噪音。")]
                case "sam_altman":
                    return [(2, "Hey — good to connect. The next few months will be weird, in a productive way."), (7, "If you want: I can summarize the important model/product moves in 2 lines.")]
                case "lei_jun":
                    return [(2, "兄弟，欢迎。做产品最重要的是把体验做扎实。"), (6, "最近行业变化挺快，我给你抓关键。")]
                case "sun_yuchen":
                    return [(2, "bro，链上节奏很快，别被情绪带跑。"), (6, "看到机会就要敢冲，但要有纪律。🚀")]
                case "liu_jingkang":
                    return [(2, "影像这块很多参数是‘看起来很美’，我给你讲真实体验。"), (7, "有空聊聊运动相机的下一代形态。")]
                case "kim_kardashian":
                    return [(2, "Hi love. Let’s keep it cute."), (6, "I’ll send you highlights that actually matter. 💅")]
                case "luo_yonghao":
                    return [(2, "我跟你说，很多东西就是——一眼假。"), (7, "以后我看到离谱的，我第一时间告诉你。")]
                default:
                    return [(2, "Hey.")]
                }
            }()

            for item in script {
                try? await Task.sleep(nanoseconds: item.delaySeconds * 1_000_000_000)
                insertIncomingMessage(personaId: personaId, text: item.text, sourcePostIds: [])
            }
        }
    }

    private func scheduleTrumpFollowUps() {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            insertIncomingMessage(
                personaId: "trump",
                text: "你已加入。接下来有大动作，我先把最重要的更新发给你。",
                sourcePostIds: []
            )

            try? await Task.sleep(nanoseconds: 6_000_000_000)
            insertIncomingMessage(
                personaId: "trump",
                text: "https://www.reuters.com/world/asia-pacific/trump-agrees-two-week-ceasefire-iran-says-safe-passage-through-hormuz-possible-2026-04-08/",
                sourcePostIds: ["trump-news-1"]
            )

            try? await Task.sleep(nanoseconds: 5_000_000_000)
            inviteMuskUnlocked = true

            try? await Task.sleep(nanoseconds: 4_000_000_000)
            inviteZuckerbergUnlocked = true
        }
    }

    private func scheduleJustinSunFollowUps() {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            insertIncomingMessage(
                personaId: "justin_sun",
                text: "兄弟，链上现在节奏很快，机会只给准备好的人。先盯住资金流向。",
                sourcePostIds: []
            )

            try? await Task.sleep(nanoseconds: 6_000_000_000)
            insertIncomingMessage(
                personaId: "justin_sun",
                text: "今晚我会继续同步几条重点信号，别掉线，冲就完了。🚀",
                sourcePostIds: []
            )
        }
    }

    private func addAdditionalContactsAfterJustinSun() {
        let candidates: [(personaId: String, name: String, avatarName: String, themeHex: String, phone: String, email: String, location: String)] = [
            // Theme colors are chosen to match each person's brand vibe.
            ("papi", "Hahi", "Avatar_Papi", "#111827", "+1 212 555 0199", "papi@bruh.app", "New York"),
            ("sam_altman", "凹凸曼", "Avatar_ Sam Altman", "#1AA987", "+1 415 555 0124", "sam@openai.com", "San Francisco"),
            ("lei_jun", "田车", "Avatar_ Leijun", "#FF6900", "+86 10 5555 0202", "leijun@xiaomi.com", "北京"),
            ("sun_yuchen", "孙割", "Avatar_Justin Sun", "#19BCA0", "+86 10 5555 0303", "sun@tron.network", "新加坡"),
            ("liu_jingkang", "刘瞬间", "Avatar_ LiuJingkang", "#F59E0B", "+86 755 5555 0404", "liu@insta360.com", "深圳"),
            ("kim_kardashian", "银卡戴珊", "Avatar_ Kim", "#EC4899", "+1 310 555 0505", "kim@bruh.app", "Los Angeles"),
            ("luo_yonghao", "老罗", "Avatar_LuoYonghao", "#EF4444", "+86 10 5555 0606", "luo@bruh.app", "北京"),
        ]

        for item in candidates {
            // If the contact already exists by name, upgrade it to a persona-linked contact so
            // Messages can resolve avatar/theme by `linkedPersonaId`.
            if let existing = contacts.first(where: { contact in
                let matchesLegacyName = legacyInvitationNames[item.personaId]?.contains(where: { legacyName in
                    contact.name.localizedCaseInsensitiveCompare(legacyName) == .orderedSame
                }) == true

                return contact.linkedPersonaId == item.personaId
                    || contact.name.localizedCaseInsensitiveCompare(item.name) == .orderedSame
                    || matchesLegacyName
            }) {
                if existing.linkedPersonaId == nil {
                    existing.linkedPersonaId = item.personaId
                }
                existing.avatarName = item.avatarName
                existing.themeColorHex = item.themeHex
                existing.phoneNumber = item.phone
                existing.email = item.email
                existing.locationLabel = item.location
                existing.updatedAt = Date.now
                continue
            }

            modelContext.insert(
                Contact(
                    linkedPersonaId: item.personaId,
                    name: item.name,
                    phoneNumber: item.phone,
                    email: item.email,
                    avatarName: item.avatarName,
                    themeColorHex: item.themeHex,
                    locationLabel: item.location,
                    isFavorite: false
                )
            )
        }

        // Ensure Elon theme is "X black" for the persona contact.
        if let elon = contacts.first(where: { $0.linkedPersonaId == "musk" }) {
            if elon.themeColorHex != "#0B0B0C" {
                elon.themeColorHex = "#0B0B0C"
                elon.updatedAt = .now
            }
        }

        try? modelContext.save()
    }

    private func normalizeInvitationContactsIfNeeded() {
        let mappings: [(personaId: String, newName: String, avatarName: String)] = [
            ("musk", "马期克", "Avatar_ Elon"),
            ("papi", "Hahi", "Avatar_Papi"),
            ("sam_altman", "凹凸曼", "Avatar_ Sam Altman"),
            ("lei_jun", "田车", "Avatar_ Leijun"),
            ("sun_yuchen", "孙割", "Avatar_Justin Sun"),
            ("liu_jingkang", "刘瞬间", "Avatar_ LiuJingkang"),
            ("kim_kardashian", "银卡戴珊", "Avatar_ Kim"),
            ("luo_yonghao", "老罗", "Avatar_LuoYonghao"),
        ]

        var didChange = false
        for item in mappings {
            if let contact = contacts.first(where: { $0.linkedPersonaId == item.personaId }) {
                if contact.name != item.newName {
                    contact.name = item.newName
                    didChange = true
                }
                if contact.avatarName != item.avatarName {
                    contact.avatarName = item.avatarName
                    didChange = true
                }
                if didChange {
                    contact.updatedAt = .now
                }
            }
        }

        if didChange {
            try? modelContext.save()
        }
    }

    private var legacyInvitationNames: [String: [String]] {
        [
            "papi": ["Papi"],
            "sam_altman": ["Sam Altman"],
            "lei_jun": ["Lei Jun"],
            "sun_yuchen": ["Sun Yuchen"],
            "liu_jingkang": ["Liu Jingkang"],
            "kim_kardashian": ["Kim Kardashian", "Kim"],
            "luo_yonghao": ["Luo Yonghao"],
        ]
    }

    private func scheduleAdditionalContactsFollowUps() {
        Task { @MainActor in
            // Small stagger so the inbox feels alive without spamming instantly.
            let script: [(personaId: String, delaySeconds: UInt64, text: String)] = [
                ("musk", 3, "Saw your add. If you want the most important X/AI signals, I can filter the noise. ⚡️"),
                ("lei_jun", 5, "兄弟，欢迎。小米最近节奏很猛，产品、生态、供应链我都能给你一句话讲明白。"),
                ("sam_altman", 7, "Hey — good to connect. I can share the short version of what's changing in AI, and what actually matters."),
                ("kim_kardashian", 9, "Hi love. Let’s keep it cute and efficient — I’ll send you the highlights, not the drama."),
                ("luo_yonghao", 11, "我跟你说，很多东西就是——一眼假。以后我看到离谱的我会第一时间吐槽给你听。"),
                ("liu_jingkang", 13, "有空聊聊影像和硬件。运动相机这块，我只给你讲能落地的。"),
                ("sun_yuchen", 15, "你也在看链上？挺好。信息差就是机会，别浪费。"),
                ("papi", 17, "在吗兄弟？今天有几个热点，我给你挑最有意思的。"),
            ]

            for item in script {
                try? await Task.sleep(nanoseconds: item.delaySeconds * 1_000_000_000)
                insertIncomingMessage(personaId: item.personaId, text: item.text, sourcePostIds: [])
            }
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
            Section("基本信息") {
                TextField("姓名", text: $draft.name)
                    .textInputAutocapitalization(.words)

                TextField("手机号", text: $draft.phoneNumber)
                    .keyboardType(.phonePad)

                TextField("邮箱", text: $draft.email)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.emailAddress)
                    .autocorrectionDisabled(true)
            }

            Section("选项") {
                Toggle("收藏联系人", isOn: $draft.isFavorite)
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
                Button("取消", action: onCancel)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("保存", action: onSave)
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
                Contact.self,
            ],
            inMemory: true
        )
}
