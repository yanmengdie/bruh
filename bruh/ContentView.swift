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
            .tabItem {
                Label("message", systemImage: "message.fill")
            }
            .badge(totalUnreadMessages > 0 ? Text("\(totalUnreadMessages)") : nil)
            .tag(MainTab.messages)

            NavigationStack {
                FeedView()
            }
            .tabItem {
                Label("朋友圈", systemImage: "globe")
            }
            .badge(totalUnreadMoments > 0 ? Text("\(totalUnreadMoments)") : nil)
            .tag(MainTab.feed)

            NavigationStack {
                albumView
            }
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
            try? messageService.ensureThreadsExist(modelContext: modelContext)
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

    private var albumView: some View {
        ScrollView {
            VStack(spacing: 14) {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 34))
                    .foregroundStyle(.secondary)
                    .padding(.top, 18)

                Text("Album")
                    .font(.system(size: 24, weight: .bold))

                Text("这里将展示你的照片与回忆。")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 20)
            .padding(.bottom, 28)
        }
        .navigationTitle("")
    }
}

private enum MainTab: Hashable {
    case contacts
    case messages
    case feed
    case album
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
    @State private var editingContact: Contact?
    @State private var draft = ContactDraft()
    @State private var validationError: String?

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

    var body: some View {
        List {
            if filteredContacts.isEmpty {
                ContentUnavailableView(
                    searchText.isEmpty ? "No Contacts" : "No Results",
                    systemImage: searchText.isEmpty ? "person.crop.circle.badge.plus" : "magnifyingglass",
                    description: Text(searchText.isEmpty ? "Tap + to add your first contact." : "Try another name, phone number, or email.")
                )
                .frame(maxWidth: .infinity, alignment: .center)
                .listRowBackground(Color.clear)
            } else {
                ForEach(filteredContacts, id: \.id) { contact in
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
                }
            }
        }
        .listStyle(.plain)
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always))
        .navigationTitle("Contacts")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    startCreating()
                } label: {
                    Image(systemName: "plus")
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
        .task {
            seedContactsIfNeeded()
        }
    }

    private func contactRow(_ contact: Contact) -> some View {
        HStack(spacing: 12) {
            Circle()
                .fill(contact.isFavorite ? Color.orange.opacity(0.2) : Color.blue.opacity(0.15))
                .frame(width: 44, height: 44)
                .overlay {
                    Text(String(contact.name.prefix(1)).uppercased())
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(contact.isFavorite ? .orange : .blue)
                }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(contact.name)
                        .font(.system(size: 16, weight: .medium))
                    if contact.isFavorite {
                        Image(systemName: "star.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.orange)
                    }
                }

                Text(contact.phoneNumber)
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)

                if !contact.email.isEmpty {
                    Text(contact.email)
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
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

    private func seedContactsIfNeeded() {
        seedSystemContacts(into: modelContext)
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
