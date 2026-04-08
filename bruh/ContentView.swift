import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\MessageThread.lastMessageAt, order: .reverse)]) private var threads: [MessageThread]
    @Query(sort: [SortDescriptor(\PersonaPost.publishedAt, order: .reverse)]) private var posts: [PersonaPost]
    @Query(sort: [SortDescriptor(\Contact.name, order: .forward)]) private var contacts: [Contact]
    @AppStorage("hasOpenedAlbum") private var hasOpenedAlbum = false
    @AppStorage("lastViewedFeedAt") private var lastViewedFeedAtInterval: Double = 0

    @State private var selectedTab: MainTab = .contacts
    @State private var messageService = MessageService()

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                ContactsView()
            }
            .enableUnifiedSwipeBack()
            .tabItem {
                Label("Contacts", systemImage: "person.crop.circle.fill")
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
                Label("message", systemImage: "message.fill")
            }
            .badge(totalUnreadMessages > 0 ? Text("\(totalUnreadMessages)") : nil)
            .tag(MainTab.messages)

            NavigationStack {
                FeedView()
            }
            .enableUnifiedSwipeBack()
            .tabItem {
                Label("朋友圈", systemImage: "globe")
            }
            .badge(totalUnreadMoments > 0 ? Text("\(totalUnreadMoments)") : nil)
            .tag(MainTab.feed)

            NavigationStack {
                AlbumView()
            }
            .enableUnifiedSwipeBack()
            .tabItem {
                Label("album", systemImage: "photo.on.rectangle.angled")
            }
            .badge(!hasOpenedAlbum ? Text("NEW") : nil)
            .tag(MainTab.album)
        }
        .onChange(of: selectedTab) { _, newValue in
            if newValue == .feed {
                lastViewedFeedAtInterval = Date().timeIntervalSince1970
            }
            if newValue == .album {
                hasOpenedAlbum = true
            }
        }
        .task {
            try? await messageService.ensureThreadsExist(modelContext: modelContext, userInterests: InterestPreferences.selectedInterests())
        }
        .toolbarBackground(AppTheme.messagesBackground, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .onAppear(perform: configureTabBarAppearance)
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

    private func configureTabBarAppearance() {
        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor(AppTheme.messagesBackground)
        appearance.shadowColor = UIColor.black.withAlphaComponent(0.05)
        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
    }
}

private enum MainTab: Hashable {
    case contacts
    case messages
    case feed
    case album
}

private struct AlbumView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                topBar
                    .padding(.top, 8)

                sectionTitle(
                    title: "Recents",
                    subtitle: "Today — 128 photos & videos"
                )

                recentsMosaic
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                sectionTitle(
                    title: "Yesterday",
                    subtitle: "Apr 7 — 84 photos & videos"
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
            Text("ALBUM")
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

    @State private var searchText = ""
    @State private var isPresentingForm = false
    @State private var presentedInvitation: BruhInvitation?
    @State private var editingContact: Contact?
    @State private var draft = ContactDraft()
    @State private var validationError: String?
    @State private var activeIndexLetter: String?
    @State private var lastIndexFeedbackLetter: String?
    @AppStorage("invite_flow_initialized") private var inviteFlowInitialized = false
    @AppStorage("invite_trump_accepted") private var inviteTrumpAccepted = false
    @AppStorage("invite_musk_unlocked") private var inviteMuskUnlocked = false
    @AppStorage("invite_musk_accepted") private var inviteMuskAccepted = false
    @AppStorage("invite_zuckerberg_unlocked") private var inviteZuckerbergUnlocked = false
    @AppStorage("invite_zuckerberg_accepted") private var inviteZuckerbergAccepted = false
    private static let alphabet: [String] = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ").map(String.init) + ["#"]

    private var filteredContacts: [Contact] {
        let sorted = contacts.sorted {
            if $0.isFavorite != $1.isFavorite { return $0.isFavorite && !$1.isFavorite }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
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
        if !inviteTrumpAccepted { items.append(.trump) }
        if inviteMuskUnlocked, !inviteMuskAccepted { items.append(.musk) }
        if inviteZuckerbergUnlocked, !inviteZuckerbergAccepted { items.append(.zuckerberg) }
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
                            searchText.isEmpty ? "No Contacts" : "No Results",
                            systemImage: searchText.isEmpty ? "person.crop.circle.badge.plus" : "magnifyingglass",
                            description: Text(searchText.isEmpty ? "Tap New Bruhs to add your first contact." : "Try another name, phone number, or email.")
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
                    title: editingContact == nil ? "New Contact" : "Edit Contact",
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
                onAccept: acceptInvitation
            )
        }
        .task {
            bootstrapInviteFlowIfNeeded()
            restoreInviteFlowIfNeeded()
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
                Text("You")
                    .font(.system(size: 21, weight: .bold))
                    .foregroundStyle(Color.black.opacity(0.86))
                Text("bruh ID: @yourboi")
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
                title: "New Bruhs",
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
                title: "Group Chats",
                action: {}
            )

            Divider().opacity(0.28)

            quickActionRow(
                icon: "🏷️",
                iconBackground: Color(red: 0.84, green: 0.89, blue: 0.82),
                title: "Tags",
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
        guard let first = contact.name.trimmingCharacters(in: .whitespacesAndNewlines).uppercased().first else {
            return "#"
        }
        let key = String(first)
        return Self.alphabet.contains(key) ? key : "#"
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
                Button("Delete", role: .destructive) {
                    delete(contact)
                }

                Button("Edit") {
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
                    Text(String(contact.name.prefix(1)).uppercased())
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(themeColor)
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
        guard let invitation = pendingInvitations.first else { return }
        presentedInvitation = invitation
    }

    private func acceptInvitation(_ invitation: BruhInvitation) {
        addContactIfNeeded(for: invitation)

        switch invitation.personaId {
        case "trump":
            inviteTrumpAccepted = true
            scheduleTrumpFollowUps()
        case "musk":
            inviteMuskAccepted = true
        case "zuckerberg":
            inviteZuckerbergAccepted = true
        default:
            break
        }
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
        inviteMuskUnlocked = false
        inviteMuskAccepted = false
        inviteZuckerbergUnlocked = false
        inviteZuckerbergAccepted = false
        inviteFlowInitialized = true
        try? modelContext.save()
    }

    private func restoreInviteFlowIfNeeded() {
        guard contacts.isEmpty, pendingInvitations.isEmpty else { return }

        inviteTrumpAccepted = false
        inviteMuskUnlocked = false
        inviteMuskAccepted = false
        inviteZuckerbergUnlocked = false
        inviteZuckerbergAccepted = false
    }

    private func addContactIfNeeded(for invitation: BruhInvitation) {
        let alreadyExists = contacts.contains { contact in
            contact.linkedPersonaId == invitation.personaId
                || contact.name.localizedCaseInsensitiveCompare(invitation.displayName) == .orderedSame
        }
        guard !alreadyExists else { return }

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

            try? await Task.sleep(nanoseconds: 5_000_000_000)
            inviteMuskUnlocked = true

            try? await Task.sleep(nanoseconds: 4_000_000_000)
            inviteZuckerbergUnlocked = true
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
                MessageThread.self,
                PersonaMessage.self,
                FeedComment.self,
                FeedLike.self,
                Contact.self,
            ],
            inMemory: true
        )
}
