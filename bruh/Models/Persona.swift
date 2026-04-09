import Foundation
import SwiftData

enum ContactRelationshipStatus: String, CaseIterable {
    case locked
    case pending
    case accepted
    case ignored
    case custom
}

struct PersonaPlatformAccount: Codable, Hashable {
    let platform: String
    let handle: String
    let profileUrl: String?
    let isPrimary: Bool
    let isActive: Bool
}

struct PersonaCatalogEntry {
    let id: String
    let displayName: String
    let avatarName: String
    let handle: String
    let domains: [String]
    let stance: String
    let triggerKeywords: [String]
    let leadInterestIds: [String]
    let xUsername: String
    let subtitle: String
    let inviteMessage: String
    let themeColorHex: String
    let locationLabel: String
    let inviteOrder: Int
    let aliases: [String]
    let entityKeywords: [String]
    let primaryLanguage: String
    let friendGreeting: String
    let defaultVoiceSpeakerId: String
    let defaultVoiceLabel: String
    let socialCircleIds: [String]
    let relationshipHints: [String: String]
    let platformAccounts: [PersonaPlatformAccount]

    func makePersona() -> Persona {
        Persona(
            id: id,
            displayName: displayName,
            avatarName: avatarName,
            handle: handle,
            domains: domains,
            stance: stance,
            triggerKeywords: triggerKeywords,
            xUsername: xUsername,
            subtitle: subtitle,
            inviteMessage: inviteMessage,
            themeColorHex: themeColorHex,
            locationLabel: locationLabel,
            inviteOrder: inviteOrder
        )
    }
}

private struct PersonaCatalogResourceEntry: Decodable {
    let id: String
    let displayName: String
    let avatarName: String
    let handle: String
    let domains: [String]
    let stance: String
    let triggerKeywords: [String]
    let entityKeywords: [String]
    let leadInterestIds: [String]
    let subtitle: String
    let inviteMessage: String
    let themeColorHex: String
    let locationLabel: String
    let baseInviteOrder: Int
    let primaryLanguage: String
    let friendGreeting: String
    let aliases: [String]
    let platformAccounts: [PersonaPlatformAccount]
    let defaultVoiceSpeakerId: String
    let defaultVoiceLabel: String
    let socialCircleIds: [String]
    let relationshipHints: [String: String]

    func makeCatalogEntry() -> PersonaCatalogEntry {
        let primaryXAccount = platformAccounts.first(where: { $0.platform == "x" && $0.isActive })?.handle ?? ""
        return PersonaCatalogEntry(
            id: id,
            displayName: displayName,
            avatarName: avatarName,
            handle: handle,
            domains: domains,
            stance: stance,
            triggerKeywords: triggerKeywords,
            leadInterestIds: leadInterestIds,
            xUsername: primaryXAccount,
            subtitle: subtitle,
            inviteMessage: inviteMessage,
            themeColorHex: themeColorHex,
            locationLabel: locationLabel,
            inviteOrder: baseInviteOrder,
            aliases: aliases,
            entityKeywords: entityKeywords,
            primaryLanguage: primaryLanguage,
            friendGreeting: friendGreeting,
            defaultVoiceSpeakerId: defaultVoiceSpeakerId,
            defaultVoiceLabel: defaultVoiceLabel,
            socialCircleIds: socialCircleIds,
            relationshipHints: relationshipHints,
            platformAccounts: platformAccounts
        )
    }
}

private final class PersonaCatalogBundleMarker: NSObject {}

enum PersonaCatalog {
    private static let loadedEntries: [PersonaCatalogEntry] = loadEntries()

    static var trump: PersonaCatalogEntry { requiredEntry(for: "trump") }
    static var musk: PersonaCatalogEntry { requiredEntry(for: "musk") }
    static var samAltman: PersonaCatalogEntry { requiredEntry(for: "sam_altman") }
    static var zhangPeng: PersonaCatalogEntry { requiredEntry(for: "zhang_peng") }
    static var leiJun: PersonaCatalogEntry { requiredEntry(for: "lei_jun") }
    static var liuJingkang: PersonaCatalogEntry { requiredEntry(for: "liu_jingkang") }
    static var luoYonghao: PersonaCatalogEntry { requiredEntry(for: "luo_yonghao") }
    static var justinSun: PersonaCatalogEntry { requiredEntry(for: "justin_sun") }
    static var kimKardashian: PersonaCatalogEntry { requiredEntry(for: "kim_kardashian") }
    static var papi: PersonaCatalogEntry { requiredEntry(for: "papi") }
    static var kobeBryant: PersonaCatalogEntry { requiredEntry(for: "kobe_bryant") }

    static var all: [PersonaCatalogEntry] {
        loadedEntries
    }

    static func entry(for personaId: String) -> PersonaCatalogEntry? {
        loadedEntries.first(where: { $0.id == personaId })
    }

    static func friendGreeting(for personaId: String) -> String {
        entry(for: personaId)?.friendGreeting ?? "我已添加你了，直接开始聊天吧。"
    }

    static func inviteOrderMap(for selectedInterestIds: [String]) -> [String: Int] {
        Dictionary(
            uniqueKeysWithValues: prioritizedEntries(for: selectedInterestIds)
                .enumerated()
                .map { ($0.element.id, $0.offset) }
        )
    }

    private static func prioritizedEntries(for selectedInterestIds: [String]) -> [PersonaCatalogEntry] {
        let normalizedInterests = orderedUnique(selectedInterestIds)

        return loadedEntries.sorted { left, right in
            let leftScore = invitePriorityScore(for: left, selectedInterestIds: normalizedInterests)
            let rightScore = invitePriorityScore(for: right, selectedInterestIds: normalizedInterests)

            if leftScore != rightScore {
                return leftScore > rightScore
            }

            return left.inviteOrder < right.inviteOrder
        }
    }

    private static func invitePriorityScore(for entry: PersonaCatalogEntry, selectedInterestIds: [String]) -> Int {
        guard !selectedInterestIds.isEmpty else { return 0 }

        let overlap = selectedInterestIds.filter(entry.domains.contains)
        let overlapScore = overlap.count * 100
        let orderedBonus = overlap.enumerated().reduce(0) { partial, element in
            partial + max(0, 60 - element.offset * 15)
        }

        let primaryBoost: Int
        if let primaryInterestId = selectedInterestIds.first {
            if primaryLeadPersonaId(for: primaryInterestId) == entry.id {
                primaryBoost = 1000
            } else if entry.domains.contains(primaryInterestId) {
                primaryBoost = 600
            } else {
                primaryBoost = 0
            }
        } else {
            primaryBoost = 0
        }

        return primaryBoost + overlapScore + orderedBonus
    }

    private static func primaryLeadPersonaId(for interestId: String) -> String? {
        loadedEntries
            .filter { $0.leadInterestIds.contains(interestId) }
            .min(by: { $0.inviteOrder < $1.inviteOrder })?
            .id ??
        loadedEntries
            .filter { $0.domains.contains(interestId) }
            .min(by: { $0.inviteOrder < $1.inviteOrder })?
            .id
    }

    private static func loadEntries() -> [PersonaCatalogEntry] {
        let decoder = JSONDecoder()
        for bundle in candidateBundles() {
            guard let url = bundle.url(forResource: "SharedPersonas", withExtension: "json"),
                  let data = try? Data(contentsOf: url),
                  let decoded = try? decoder.decode([PersonaCatalogResourceEntry].self, from: data) else {
                continue
            }

            return decoded
                .map { $0.makeCatalogEntry() }
                .sorted { $0.inviteOrder < $1.inviteOrder }
        }

        assertionFailure("SharedPersonas.json could not be loaded from the app bundle.")
        return []
    }

    private static func candidateBundles() -> [Bundle] {
        let bundles = [
            Bundle.main,
            Bundle(for: PersonaCatalogBundleMarker.self),
        ]

        var seen = Set<String>()
        var result: [Bundle] = []
        for bundle in bundles where seen.insert(bundle.bundlePath).inserted {
            result.append(bundle)
        }
        return result
    }

    private static func orderedUnique<T: Hashable>(_ values: [T]) -> [T] {
        var seen = Set<T>()
        var result: [T] = []
        for value in values where seen.insert(value).inserted {
            result.append(value)
        }
        return result
    }

    private static func requiredEntry(for personaId: String) -> PersonaCatalogEntry {
        guard let entry = entry(for: personaId) else {
            fatalError("Missing persona catalog entry for \(personaId)")
        }
        return entry
    }
}

@Model
final class Persona {
    @Attribute(.unique) var id: String
    var displayName: String
    var avatarName: String   // asset name in Assets.xcassets
    var handle: String       // e.g. "@elonmusk"
    var domains: [String]    // e.g. ["tech","ai","space"]
    var stance: String       // personality description
    var triggerKeywords: [String]
    var xUsername: String    // actual X handle for API
    var subtitle: String
    var inviteMessage: String
    var themeColorHex: String
    var locationLabel: String
    var inviteOrder: Int

    init(
        id: String,
        displayName: String,
        avatarName: String,
        handle: String,
        domains: [String],
        stance: String,
        triggerKeywords: [String],
        xUsername: String,
        subtitle: String,
        inviteMessage: String,
        themeColorHex: String,
        locationLabel: String,
        inviteOrder: Int
    ) {
        self.id = id
        self.displayName = displayName
        self.avatarName = avatarName
        self.handle = handle
        self.domains = domains
        self.stance = stance
        self.triggerKeywords = triggerKeywords
        self.xUsername = xUsername
        self.subtitle = subtitle
        self.inviteMessage = inviteMessage
        self.themeColorHex = themeColorHex
        self.locationLabel = locationLabel
        self.inviteOrder = inviteOrder
    }
}

extension Persona {
    static var all: [Persona] {
        PersonaCatalog.all.map { $0.makePersona() }
    }
}

@Model
final class UserProfile {
    @Attribute(.unique) var id: String
    var displayName: String
    var bruhHandle: String
    @Attribute(.externalStorage) var avatarImageData: Data?
    var selectedInterestIds: [String]
    var timezoneIdentifier: String
    var onboardingCompletedAt: Date?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: String = CurrentUserProfileStore.userId,
        displayName: String = "You",
        bruhHandle: String = "@yourboi",
        avatarImageData: Data? = nil,
        selectedInterestIds: [String] = NewsInterest.defaultSelection.map(\.rawValue),
        timezoneIdentifier: String = TimeZone.current.identifier,
        onboardingCompletedAt: Date? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.displayName = displayName
        self.bruhHandle = bruhHandle
        self.avatarImageData = avatarImageData
        self.selectedInterestIds = selectedInterestIds
        self.timezoneIdentifier = timezoneIdentifier
        self.onboardingCompletedAt = onboardingCompletedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

@Model
final class Contact {
    @Attribute(.unique) var id: UUID
    var linkedPersonaId: String?
    var name: String
    var phoneNumber: String
    var email: String
    var avatarName: String
    var themeColorHex: String
    var locationLabel: String
    var isFavorite: Bool
    var relationshipStatus: String
    var inviteOrder: Int?
    var acceptedAt: Date?
    var ignoredAt: Date?
    var affinityScore: Double
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        linkedPersonaId: String? = nil,
        name: String,
        phoneNumber: String,
        email: String = "",
        avatarName: String = "Avatar",
        themeColorHex: String = "#3B82F6",
        locationLabel: String = "",
        isFavorite: Bool = false,
        relationshipStatus: String = ContactRelationshipStatus.custom.rawValue,
        inviteOrder: Int? = nil,
        acceptedAt: Date? = nil,
        ignoredAt: Date? = nil,
        affinityScore: Double = 0.5,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.linkedPersonaId = linkedPersonaId
        self.name = name
        self.phoneNumber = phoneNumber
        self.email = email
        self.avatarName = avatarName
        self.themeColorHex = themeColorHex
        self.locationLabel = locationLabel
        self.isFavorite = isFavorite
        self.relationshipStatus = relationshipStatus
        self.inviteOrder = inviteOrder
        self.acceptedAt = acceptedAt
        self.ignoredAt = ignoredAt
        self.affinityScore = affinityScore
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

extension Contact {
    var relationshipStatusValue: ContactRelationshipStatus {
        get { ContactRelationshipStatus(rawValue: relationshipStatus) ?? .custom }
        set { relationshipStatus = newValue.rawValue }
    }

    var isVisibleInContactsList: Bool {
        switch relationshipStatusValue {
        case .accepted, .custom:
            return true
        case .locked, .pending, .ignored:
            return false
        }
    }

    var isPendingInvitation: Bool {
        linkedPersonaId != nil && relationshipStatusValue == .pending
    }
}

enum CurrentUserProfileStore {
    static let userId = "viewer"

    @MainActor
    static func fetchOrCreate(in context: ModelContext) -> UserProfile {
        var descriptor = FetchDescriptor<UserProfile>(
            predicate: #Predicate { $0.id == userId }
        )
        descriptor.fetchLimit = 1

        if let existing = try? context.fetch(descriptor).first {
            migrateLegacyPreferencesIfNeeded(profile: existing)
            return existing
        }

        let profile = UserProfile(
            displayName: "You",
            bruhHandle: "@yourboi",
            selectedInterestIds: legacyOrDefaultInterests()
        )
        context.insert(profile)
        if context.hasChanges {
            try? context.save()
        }
        return profile
    }

    @MainActor
    static func selectedInterests(in context: ModelContext) -> [String] {
        fetchOrCreate(in: context).selectedInterestIds
    }

    @MainActor
    static func updateSelectedInterests(_ interestIds: [String], in context: ModelContext) {
        let profile = fetchOrCreate(in: context)
        let normalized = normalizedInterestIds(interestIds)
        profile.updatedAt = .now
        profile.selectedInterestIds = normalized
        if context.hasChanges {
            try? context.save()
        }
    }

    @MainActor
    static func completeOnboarding(
        displayName: String,
        selectedInterestIds: [String],
        avatarImageData: Data? = nil,
        in context: ModelContext
    ) {
        let profile = fetchOrCreate(in: context)
        let trimmedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        profile.displayName = trimmedName.isEmpty ? "You" : trimmedName
        profile.selectedInterestIds = normalizedInterestIds(selectedInterestIds)
        if let avatarImageData {
            profile.avatarImageData = avatarImageData
        }
        profile.onboardingCompletedAt = .now
        profile.timezoneIdentifier = TimeZone.current.identifier
        profile.updatedAt = .now

        let slug = trimmedName
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined()
        if !slug.isEmpty {
            profile.bruhHandle = "@\(String(slug.prefix(18)))"
        }

        if context.hasChanges {
            try? context.save()
        }
    }

    @MainActor
    private static func migrateLegacyPreferencesIfNeeded(profile: UserProfile) {
        guard profile.selectedInterestIds.isEmpty else { return }
        profile.selectedInterestIds = legacyOrDefaultInterests()
        profile.updatedAt = .now
    }

    private static func normalizedInterestIds(_ interestIds: [String]) -> [String] {
        let normalized = interestIds
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return Array(NSOrderedSet(array: normalized)) as? [String] ?? normalized
    }

    private static func legacyOrDefaultInterests(userDefaults: UserDefaults = .standard) -> [String] {
        if let onboardingRaw = userDefaults.string(forKey: OnboardingInterestStore.userDefaultsKey), !onboardingRaw.isEmpty {
            let parsed = onboardingRaw
                .split(separator: ",")
                .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            if !parsed.isEmpty {
                return Array(NSOrderedSet(array: parsed)) as? [String] ?? parsed
            }
        }

        let legacy = InterestPreferences.legacySelectedInterests(userDefaults: userDefaults)
        if !legacy.isEmpty {
            return legacy
        }

        return NewsInterest.defaultSelection.map(\.rawValue)
    }
}
