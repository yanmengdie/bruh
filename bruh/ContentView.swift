import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\MessageThread.lastMessageAt, order: .reverse)]) private var threads: [MessageThread]
    @Query(sort: [SortDescriptor(\Contact.name, order: .forward)]) private var contacts: [Contact]

    @State private var currentDestination: AppDestination? = nil
    @State private var messageService = MessageService()

    var body: some View {
        ZStack {
            if let destination = currentDestination {
                destinationView(for: destination)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(.move(edge: .trailing))
            } else {
                HomeScreen(onNavigate: { destination in
                    withAnimation(.easeInOut(duration: 0.25)) {
                        currentDestination = destination
                    }
                })
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.easeInOut(duration: 0.25), value: currentDestination)
        .task {
            try? messageService.ensureThreadsExist(modelContext: modelContext)
        }
    }

    @ViewBuilder
    private func destinationView(for destination: AppDestination) -> some View {
        switch destination {
        case .feed:
            NavigationStack {
                FeedView()
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            backButton
                        }
                    }
            }
            .swipeBackGesture(onBack: goBackToHome)

        case .imessage:
            NavigationStack {
                ScrollView {
                    VStack(spacing: 14) {
                        messageSearchBar
                            .padding(.horizontal, 16)

                        VStack(spacing: 0) {
                            ForEach(Array(threads.enumerated()), id: \.element.id) { index, thread in
                                NavigationLink {
                                    MessageDetailView(thread: thread, service: messageService)
                                } label: {
                                    messageRow(thread: thread)
                                }
                                .buttonStyle(.plain)

                                if index < threads.count - 1 {
                                    divider
                                }
                            }
                        }
                        .background(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .padding(.horizontal, 16)
                    }
                    .padding(.top, 10)
                    .padding(.bottom, 20)
                }
                .background(Color(red: 0.95, green: 0.96, blue: 0.98))
                .navigationTitle("Messages")
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        backButton
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Image(systemName: "square.and.pencil")
                    }
                }
            }
            .swipeBackGesture(onBack: goBackToHome)

        case .contacts:
            NavigationStack {
                ContactsView()
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            backButton
                        }
                    }
            }
            .swipeBackGesture(onBack: goBackToHome)

        case .settings:
            NavigationStack {
                List {
                    Label("通知设置", systemImage: "bell.badge")
                    Label("内容偏好", systemImage: "slider.horizontal.3")
                    Label("关于 Bruh", systemImage: "info.circle")
                }
                .navigationTitle("设置")
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        backButton
                    }
                }
            }
            .swipeBackGesture(onBack: goBackToHome)
        }
    }

    private var backButton: some View {
        Button {
            goBackToHome()
        } label: {
            Image(systemName: "chevron.left")
        }
    }

    private func goBackToHome() {
        withAnimation {
            currentDestination = nil
        }
    }

    private var messageSearchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            Text("搜索")
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.black.opacity(0.06))
            .frame(height: 0.5)
            .padding(.leading, 74)
    }

    private func messageRow(thread: MessageThread) -> some View {
        let persona = persona(for: thread.personaId)

        return HStack(spacing: 12) {
            Circle()
                .fill(persona.tint.opacity(0.18))
                .frame(width: 50, height: 50)
                .overlay {
                    Text(String(persona.name.prefix(1)))
                        .font(.headline)
                        .foregroundStyle(persona.tint)
                }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(persona.name)
                        .font(.system(size: 16, weight: thread.unreadCount > 0 ? .semibold : .regular))
                        .foregroundStyle(.primary)
                    Spacer()
                    Text(relativeTime(thread.lastMessageAt))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Text(thread.lastMessagePreview.isEmpty ? "Start the conversation" : thread.lastMessagePreview)
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Spacer()

                    if thread.unreadCount > 0 {
                        Text("\(thread.unreadCount)")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Color.blue)
                            .clipShape(Capsule())
                    }
                }
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private func persona(for personaId: String) -> (name: String, tint: Color) {
        if let contact = contacts.first(where: { $0.linkedPersonaId == personaId }) {
            return (contact.name, tint(for: personaId))
        }

        return (personaId.capitalized, tint(for: personaId))
    }

    private func tint(for personaId: String) -> Color {
        switch personaId {
        case "trump":
            return .orange
        case "musk":
            return .blue
        case "zuckerberg":
            return .purple
        default:
            return .gray
        }
    }

    private func relativeTime(_ date: Date) -> String {
        guard date > Date.distantPast else { return "Now" }

        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

private struct MessageDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var messages: [PersonaMessage]
    @Query(sort: [SortDescriptor(\Contact.name, order: .forward)]) private var contacts: [Contact]

    let thread: MessageThread
    let service: MessageService

    @State private var draft = ""
    @State private var isSending = false
    @State private var errorMessage: String?

    init(thread: MessageThread, service: MessageService) {
        self.thread = thread
        self.service = service
        let threadId = thread.id
        _messages = Query(
            filter: #Predicate<PersonaMessage> { $0.threadId == threadId },
            sort: [SortDescriptor(\PersonaMessage.createdAt, order: .forward)]
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 14) {
                        Text("Messages with \(displayName)")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .padding(.top, 8)

                        LazyVStack(spacing: 10) {
                            ForEach(messages, id: \.id) { message in
                                HStack {
                                    if message.isIncoming {
                                        bubble(text: message.text, isIncoming: true, deliveryState: message.deliveryState)
                                        Spacer(minLength: 48)
                                    } else {
                                        Spacer(minLength: 48)
                                        bubble(text: message.text, isIncoming: false, deliveryState: message.deliveryState)
                                    }
                                }
                                .id(message.id)
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 12)
                }
                .onChange(of: messages.count) {
                    if let last = messages.last {
                        withAnimation {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }

            VStack(spacing: 8) {
                if let errorMessage {
                    Text(errorMessage)
                        .font(.system(size: 12))
                        .foregroundStyle(.red)
                        .padding(.horizontal, 12)
                }

                Divider()

                HStack(alignment: .bottom, spacing: 8) {
                    Button {} label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 24))
                            .foregroundStyle(.blue)
                    }

                    HStack(alignment: .bottom, spacing: 8) {
                        Image(systemName: "camera.fill")
                            .foregroundStyle(.secondary)

                        TextField("iMessage", text: $draft, axis: .vertical)
                            .lineLimit(1...4)

                        Spacer()

                        if isSending {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Button {
                                send()
                            } label: {
                                Image(systemName: "arrow.up.circle.fill")
                                    .font(.system(size: 22))
                                    .foregroundStyle(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .gray : .blue)
                            }
                            .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                    .background(Color(.systemGray6))
                    .clipShape(Capsule())
                }
                .padding(.horizontal, 12)
                .padding(.top, 4)
                .padding(.bottom, 8)
            }
            .background(.ultraThinMaterial)
        }
        .background(Color.white)
        .navigationTitle(displayName)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            try? service.markThreadRead(personaId: thread.personaId, modelContext: modelContext)
        }
    }

    private var displayName: String {
        contacts.first(where: { $0.linkedPersonaId == thread.personaId })?.name ?? thread.personaId.capitalized
    }

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isSending else { return }

        draft = ""
        errorMessage = nil
        isSending = true

        Task {
            do {
                try await service.sendMessage(personaId: thread.personaId, text: text, modelContext: modelContext)
            } catch {
                errorMessage = error.localizedDescription
            }
            isSending = false
        }
    }

    private func bubble(text: String, isIncoming: Bool, deliveryState: String) -> some View {
        VStack(alignment: isIncoming ? .leading : .trailing, spacing: 4) {
            Text(text)
                .font(.system(size: 16))
                .foregroundColor(isIncoming ? .primary : .white)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(isIncoming ? Color(.systemGray5) : Color.blue)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

            if !isIncoming && deliveryState == "failed" {
                Text("Failed to send")
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
            }
        }
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
