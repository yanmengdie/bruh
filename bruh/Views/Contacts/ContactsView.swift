import SwiftUI
import SwiftData
import UIKit

private struct ContactDraft {
    var name: String = ""
    var phoneNumber: String = ""
    var email: String = ""
    var isFavorite: Bool = false
}

private struct ContactsDerivedState {
    let isSearching: Bool
    let filteredContacts: [Contact]
    let sectionedContacts: [(key: String, values: [Contact])]
    let availableSectionKeys: Set<String>
    let pendingInvitations: [BruhInvitation]
    let lockedCandidateNamesByPersonaId: [String: [String]]

    var pendingInvitationCount: Int {
        pendingInvitations.count
    }

    func lockedCandidateNames(excluding personaId: String) -> [String] {
        lockedCandidateNamesByPersonaId[personaId] ?? []
    }
}

private struct InviteContext {
    let personaById: [String: Persona]
    let matchingPersonaIds: Set<String>
    let priorityByPersonaId: [String: Int]
    let fallbackRank: Int

    func matches(personaId: String) -> Bool {
        matchingPersonaIds.contains(personaId)
    }

    func sortKey(for contact: Contact) -> (Int, Int, String) {
        let priority = contact.linkedPersonaId
            .flatMap { priorityByPersonaId[$0] } ?? fallbackRank
        let order = contact.inviteOrder ?? 999
        return (priority, order, contact.name)
    }
}

struct ContactsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\Contact.name, order: .forward)]) private var contacts: [Contact]
    @Query(sort: [SortDescriptor(\Persona.inviteOrder, order: .forward)]) private var personas: [Persona]
    @Query private var profiles: [UserProfile]

    @State private var searchText = ""
    @State private var isPresentingForm = false
    @State private var presentedInvitation: BruhInvitation?
    @State private var isPresentingAddBruh = false
    @State private var isPresentingTagContacts = false
    @State private var isPresentingProfileSettings = false
    @State private var editingContact: Contact?
    @State private var draft = ContactDraft()
    @State private var validationError: String?
    @State private var activeIndexLetter: String?
    @State private var lastIndexFeedbackLetter: String?
    @State private var messageService = MessageService()

    private static let alphabet: [String] = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ").map(String.init) + ["#"]
    private let trumpFollowUpMessageId = "demo:trump-news-1"
    private let trumpFollowUpSourcePostIds = ["trump-news-1"]
    private let trumpFollowUpURL = "https://www.reuters.com/world/asia-pacific/trump-agrees-two-week-ceasefire-iran-says-safe-passage-through-hormuz-possible-2026-04-08/"
    private let invitePersonaAllowlist: Set<String> = [
        "trump",
        "musk",
        "lei_jun",
        "luo_yonghao",
        "sam_altman",
        "papi",
        "justin_sun",
    ]

    private var currentProfile: UserProfile? {
        profiles.first(where: { $0.id == CurrentUserProfileStore.userId })
    }

    private var currentProfileAvatarImage: UIImage? {
        guard let data = currentProfile?.avatarImageData else { return nil }
        return UIImage(data: data)
    }

    var body: some View {
        let derivedState = makeDerivedState()

        ScrollViewReader { proxy in
            ZStack(alignment: .trailing) {
                List {
                    if !derivedState.isSearching {
                        topCards(pendingInvitationCount: derivedState.pendingInvitationCount)
                            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                    }

                    if derivedState.filteredContacts.isEmpty {
                        ContentUnavailableView(
                            searchText.isEmpty ? "暂无联系人" : "无搜索结果",
                            systemImage: searchText.isEmpty ? "person.crop.circle.badge.plus" : "magnifyingglass",
                            description: Text(searchText.isEmpty ? "点进“新鸽们”接收新的好友请求。" : "试试其他姓名、手机号或邮箱。")
                        )
                        .frame(maxWidth: .infinity, alignment: .center)
                        .listRowBackground(Color.clear)
                    } else if derivedState.isSearching {
                        ForEach(derivedState.filteredContacts, id: \.id) { contact in
                            contactListRow(contact)
                        }
                    } else {
                        ForEach(derivedState.sectionedContacts, id: \.key) { section in
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

                if !derivedState.isSearching && !derivedState.sectionedContacts.isEmpty {
                    alphabetIndex(proxy: proxy, availableSectionKeys: derivedState.availableSectionKeys)
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
                lockedCandidateNames: derivedState.lockedCandidateNames(excluding: invitation.personaId),
                onAccept: acceptInvitation,
                onIgnore: ignoreInvitation
            )
        }
        .navigationDestination(isPresented: $isPresentingAddBruh) {
            AddBruhView()
        }
        .navigationDestination(isPresented: $isPresentingTagContacts) {
            ContactTagsView()
        }
        .navigationDestination(isPresented: $isPresentingProfileSettings) {
            ProfileAccountView()
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
    }

    private func topCards(pendingInvitationCount: Int) -> some View {
        VStack(spacing: 12) {
            profileCard
            quickActionsCard(pendingInvitationCount: pendingInvitationCount)
        }
    }

    private var profileCard: some View {
        let rawProfileName = currentProfile?.displayName ?? "我"
        let profileName = rawProfileName == "You" ? "我" : rawProfileName
        let profileHandle = currentProfile?.bruhHandle ?? "@yourboi"

        return Button {
            isPresentingProfileSettings = true
        } label: {
            HStack(spacing: 14) {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(red: 0.84, green: 0.81, blue: 0.73))
                    .frame(width: 66, height: 66)
                    .overlay {
                        if let avatar = currentProfileAvatarImage {
                            Image(uiImage: avatar)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 66, height: 66)
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        } else {
                            Text("😎")
                                .font(.system(size: 35))
                        }
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
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(Color.white.opacity(0.68))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func quickActionsCard(pendingInvitationCount: Int) -> some View {
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
                icon: "🏷️",
                iconBackground: Color(red: 0.84, green: 0.89, blue: 0.82),
                title: "标签",
                action: openTagContacts
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

    private func alphabetIndex(proxy: ScrollViewProxy, availableSectionKeys: Set<String>) -> some View {
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
                                jumpToIndexLetter(letter, proxy: proxy, availableSectionKeys: availableSectionKeys, animated: true)
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
                            jumpToIndexLetter(letter, proxy: proxy, availableSectionKeys: availableSectionKeys, animated: false)
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

    private func jumpToIndexLetter(
        _ letter: String,
        proxy: ScrollViewProxy,
        availableSectionKeys: Set<String>,
        animated: Bool
    ) {
        guard let target = targetSection(for: letter, availableSectionKeys: availableSectionKeys) else { return }
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

    private func targetSection(for letter: String, availableSectionKeys: Set<String>) -> String? {
        guard let requestedIndex = Self.alphabet.firstIndex(of: letter) else { return nil }

        if availableSectionKeys.contains(letter) {
            return letter
        }

        for index in requestedIndex..<Self.alphabet.count where availableSectionKeys.contains(Self.alphabet[index]) {
            return Self.alphabet[index]
        }

        for index in stride(from: requestedIndex - 1, through: 0, by: -1) where availableSectionKeys.contains(Self.alphabet[index]) {
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

    private func openNewBruh() {
        normalizeInviteFrontier()
        guard let invitation = makeDerivedState().pendingInvitations.first else { return }
        presentedInvitation = invitation
    }

    private func openTagContacts() {
        isPresentingTagContacts = true
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

        let shouldScheduleTrumpFollowUps = !wasAccepted && invitation.personaId == "trump"

        do {
            try modelContext.save()
            try messageService.prepareThreads(modelContext: modelContext)
            if shouldScheduleTrumpFollowUps {
                scheduleTrumpFollowUps()
            }
        } catch {
            print("Failed to accept invitation for \(invitation.personaId): \(error.localizedDescription)")
        }

        guard !wasAccepted else { return }
        let userInterests = CurrentUserProfileStore.selectedInterests(in: modelContext)
        Task {
            await messageService.refreshStarterMessages(
                modelContext: modelContext,
                userInterests: userInterests
            )
        }
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
        let inviteContext = makeInviteContext()

        for contact in contacts {
            guard let personaId = contact.linkedPersonaId,
                  invitePersonaAllowlist.contains(personaId) else { continue }

            if !inviteContext.matches(personaId: personaId),
               contact.relationshipStatusValue == .pending {
                contact.relationshipStatusValue = .locked
                contact.updatedAt = .now
            }
        }

        let personaContacts = contacts
            .filter { contact in
                guard let personaId = contact.linkedPersonaId else { return false }
                return invitePersonaAllowlist.contains(personaId)
                    && inviteContext.matches(personaId: personaId)
            }
            .sorted { inviteContext.sortKey(for: $0) < inviteContext.sortKey(for: $1) }

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

    private func makeDerivedState() -> ContactsDerivedState {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let sortedVisibleContacts = contacts
            .filter(\.isVisibleInContactsList)
            .sorted {
                if $0.isFavorite != $1.isFavorite { return $0.isFavorite && !$1.isFavorite }
                return sortKey(for: $0.name).localizedCaseInsensitiveCompare(sortKey(for: $1.name)) == .orderedAscending
            }

        let filteredContacts: [Contact]
        if query.isEmpty {
            filteredContacts = sortedVisibleContacts
        } else {
            filteredContacts = sortedVisibleContacts.filter { contact in
                contact.name.localizedCaseInsensitiveContains(query)
                    || contact.phoneNumber.localizedCaseInsensitiveContains(query)
                    || contact.email.localizedCaseInsensitiveContains(query)
            }
        }

        let groupedContacts = Dictionary(grouping: filteredContacts, by: sectionKey)
        let sectionedContacts: [(key: String, values: [Contact])] = Self.alphabet.compactMap { key in
            guard let values = groupedContacts[key], !values.isEmpty else { return nil }
            return (key, values)
        }

        let inviteContext = makeInviteContext()
        let eligibleInviteContacts = contacts
            .filter { contact in
                guard let personaId = contact.linkedPersonaId else { return false }
                return invitePersonaAllowlist.contains(personaId)
                    && inviteContext.matches(personaId: personaId)
            }
            .sorted { inviteContext.sortKey(for: $0) < inviteContext.sortKey(for: $1) }

        let pendingInvitations: [BruhInvitation] = eligibleInviteContacts.compactMap { contact in
            guard contact.relationshipStatusValue == .pending,
                  let personaId = contact.linkedPersonaId,
                  let persona = inviteContext.personaById[personaId] else {
                return nil
            }
            return BruhInvitation(persona: persona, contact: contact)
        }

        let lockedInviteContacts = eligibleInviteContacts.filter { $0.relationshipStatusValue == .locked }
        let eligiblePersonaIds = Set(eligibleInviteContacts.compactMap(\.linkedPersonaId))
        var lockedCandidateNamesByPersonaId: [String: [String]] = [:]

        for personaId in eligiblePersonaIds {
            lockedCandidateNamesByPersonaId[personaId] = lockedInviteContacts
                .filter { $0.linkedPersonaId != personaId }
                .map(\.name)
        }

        return ContactsDerivedState(
            isSearching: !query.isEmpty,
            filteredContacts: filteredContacts,
            sectionedContacts: sectionedContacts,
            availableSectionKeys: Set(sectionedContacts.map { $0.key }),
            pendingInvitations: pendingInvitations,
            lockedCandidateNamesByPersonaId: lockedCandidateNamesByPersonaId
        )
    }

    private func makeInviteInterestOrder() -> [String] {
        let supported = Set(["politics", "entertainment", "finance", "sports", "tech"])
        let selected = CurrentUserProfileStore.selectedInterests(in: modelContext)
            .filter { supported.contains($0) }

        let deduped = Array(NSOrderedSet(array: selected)) as? [String] ?? selected
        if !deduped.isEmpty { return deduped }

        return NewsInterest.defaultSelection
            .map(\.rawValue)
            .filter { supported.contains($0) }
    }

    private func makeInviteContext() -> InviteContext {
        let inviteInterestOrder = makeInviteInterestOrder()
        let inviteInterestSet = Set(inviteInterestOrder)
        let fallbackRank = inviteInterestOrder.count + 10
        let personaById = Dictionary(uniqueKeysWithValues: personas.map { ($0.id, $0) })

        let matchingPersonaIds: Set<String> = Set(
            personas.compactMap { persona in
                guard invitePersonaAllowlist.contains(persona.id) else { return nil }
                guard !inviteInterestSet.isEmpty else { return persona.id }
                return Set(persona.domains).isDisjoint(with: inviteInterestSet) ? nil : persona.id
            }
        )

        var priorityByPersonaId: [String: Int] = [:]
        for persona in personas where invitePersonaAllowlist.contains(persona.id) {
            let rank = persona.domains
                .compactMap { inviteInterestOrder.firstIndex(of: $0) }
                .min() ?? fallbackRank
            priorityByPersonaId[persona.id] = rank
        }

        return InviteContext(
            personaById: personaById,
            matchingPersonaIds: matchingPersonaIds,
            priorityByPersonaId: priorityByPersonaId,
            fallbackRank: fallbackRank
        )
    }

    private func scheduleTrumpFollowUps() {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 11_000_000_000)
            guard contact(for: "trump")?.relationshipStatusValue == .accepted else { return }
            insertIncomingMessage(
                id: trumpFollowUpMessageId,
                personaId: "trump",
                text: trumpFollowUpURL,
                sourcePostIds: trumpFollowUpSourcePostIds
            )
        }
    }

    private func insertIncomingMessage(
        id: String = UUID().uuidString,
        personaId: String,
        text: String,
        sourcePostIds: [String]
    ) {
        guard contact(for: personaId)?.relationshipStatusValue == .accepted else { return }
        guard !messageExists(id: id) else { return }

        let threadStore = MessageThreadStore()
        let thread: MessageThread

        do {
            thread = try threadStore.ensureThread(for: personaId, modelContext: modelContext)
        } catch {
            print("Failed to ensure thread for \(personaId): \(error.localizedDescription)")
            return
        }

        let now = Date()
        let message = PersonaMessage(
            id: id,
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
        let unreadCount = threadStore.nextUnreadCount(afterReceivingMessageAt: now, on: thread)
        threadStore.updateThread(thread, preview: text, at: now, unreadCount: unreadCount)
        try? modelContext.save()
    }

    private func messageExists(id: String) -> Bool {
        let targetId = id
        var descriptor = FetchDescriptor<PersonaMessage>(
            predicate: #Predicate { $0.id == targetId }
        )
        descriptor.fetchLimit = 1
        return ((try? modelContext.fetch(descriptor)) ?? []).isEmpty == false
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
                Toggle("设为星标联系人", isOn: $draft.isFavorite)
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

private struct ProfileAccountView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var profiles: [UserProfile]

    @State private var profileImage: UIImage?
    @State private var isPresentingImagePicker = false
    @State private var isShowingImageSourceOptions = false
    @State private var imagePickerSourceType: UIImagePickerController.SourceType = .photoLibrary
    @State private var pickerAlertTitle = ""
    @State private var pickerAlertMessage = ""
    @State private var isShowingPickerAlert = false

    private var currentProfile: UserProfile? {
        profiles.first(where: { $0.id == CurrentUserProfileStore.userId })
    }

    private var profileName: String {
        let raw = currentProfile?.displayName ?? "我"
        return raw == "You" ? "我" : raw
    }

    private var profileHandle: String {
        currentProfile?.bruhHandle ?? "@yourboi"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("我的账号")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(Color.black.opacity(0.88))
                    .padding(.top, 8)

                profileSummaryCard
                avatarActionCard
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 28)
        }
        .background(AppTheme.messagesBackground)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                AppBackButton {
                    dismiss()
                }
            }
        }
        .confirmationDialog("选择头像", isPresented: $isShowingImageSourceOptions, titleVisibility: .visible) {
            Button("拍照") {
                presentImagePicker(sourceType: .camera)
            }

            Button("从相册选择") {
                presentImagePicker(sourceType: .photoLibrary)
            }

            Button("取消", role: .cancel) {}
        }
        .sheet(isPresented: $isPresentingImagePicker, onDismiss: persistAvatarIfNeeded) {
            AvatarImagePicker(
                image: $profileImage,
                sourceType: imagePickerSourceType
            )
            .ignoresSafeArea()
        }
        .alert(pickerAlertTitle, isPresented: $isShowingPickerAlert) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text(pickerAlertMessage)
        }
        .onAppear {
            loadCurrentAvatarIfNeeded()
        }
        .enableUnifiedSwipeBack()
    }

    private var profileSummaryCard: some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(red: 0.90, green: 0.88, blue: 0.84))
                .frame(width: 84, height: 84)
                .overlay {
                    if let profileImage {
                        Image(uiImage: profileImage)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 84, height: 84)
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    } else {
                        Text("😎")
                            .font(.system(size: 42))
                    }
                }

            VStack(alignment: .leading, spacing: 6) {
                Text(profileName)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Color.black.opacity(0.86))
                Text("鸽们账号：\(profileHandle)")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.black.opacity(0.34))
                Text("更换头像后，会同步到联系人、消息和朋友圈。")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.black.opacity(0.42))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .background(Color.white.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private var avatarActionCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("头像设置")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(Color.black.opacity(0.72))

            HStack(spacing: 18) {
                avatarPickerButton

                VStack(alignment: .leading, spacing: 8) {
                    Text("重新设置头像")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(Color.black.opacity(0.84))
                    Text("支持拍照或从相册选择，逻辑和首次 onboarding 保持一致。")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color.black.opacity(0.42))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }
        }
        .padding(18)
        .background(Color.white.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private var avatarPickerButton: some View {
        Button {
            isShowingImageSourceOptions = true
        } label: {
            ZStack(alignment: .bottomTrailing) {
                Circle()
                    .fill(Color(red: 0.90, green: 0.88, blue: 0.84))
                    .frame(width: 92, height: 92)
                    .overlay {
                        Circle()
                            .stroke(Color.black.opacity(0.12), style: StrokeStyle(lineWidth: 5, dash: [10, 5]))
                    }
                    .overlay {
                        if let profileImage {
                            Image(uiImage: profileImage)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 80, height: 80)
                                .clipShape(Circle())
                        } else {
                            Text("📸")
                                .font(.system(size: 36))
                        }
                    }

                Circle()
                    .fill(Color(red: 0.10, green: 0.11, blue: 0.13))
                    .frame(width: 30, height: 30)
                    .overlay {
                        Image(systemName: "plus")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    .offset(x: 2, y: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("重新设置头像")
    }

    private func loadCurrentAvatarIfNeeded() {
        guard profileImage == nil,
              let data = currentProfile?.avatarImageData,
              let image = UIImage(data: data) else { return }
        profileImage = image
    }

    private func persistAvatarIfNeeded() {
        let newData = profileImage?.jpegData(compressionQuality: 0.85)
        guard newData != currentProfile?.avatarImageData else { return }
        CurrentUserProfileStore.updateAvatarImageData(newData, in: modelContext)
    }

    private func presentImagePicker(sourceType: UIImagePickerController.SourceType) {
        guard UIImagePickerController.isSourceTypeAvailable(sourceType) else {
            switch sourceType {
            case .camera:
                pickerAlertTitle = "当前设备无法打开相机"
                pickerAlertMessage = "请在支持相机的设备上重试，或改为从相册选择。"
            case .photoLibrary, .savedPhotosAlbum:
                pickerAlertTitle = "当前设备无法访问相册"
                pickerAlertMessage = "请检查系统权限后重试。"
            @unknown default:
                pickerAlertTitle = "当前设备无法选择图片"
                pickerAlertMessage = "请稍后重试。"
            }
            isShowingPickerAlert = true
            return
        }

        imagePickerSourceType = sourceType
        isPresentingImagePicker = true
    }
}
