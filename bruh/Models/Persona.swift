import Foundation
import SwiftData

enum ContactRelationshipStatus: String, CaseIterable {
    case locked
    case pending
    case accepted
    case ignored
    case custom
}

struct PersonaCatalogEntry {
    let id: String
    let displayName: String
    let avatarName: String
    let handle: String
    let domains: [String]
    let stance: String
    let triggerKeywords: [String]
    let xUsername: String
    let subtitle: String
    let inviteMessage: String
    let themeColorHex: String
    let locationLabel: String
    let inviteOrder: Int

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

enum PersonaCatalog {
    static let trump = PersonaCatalogEntry(
        id: "trump",
        displayName: "Donald Trump",
        avatarName: "avatar_trump",
        handle: "@realDonaldTrump",
        domains: ["politics", "finance", "trade"],
        stance: "美国优先, 反建制, 自我吹嘘, 攻击对手",
        triggerKeywords: ["tariff", "china", "trade", "election", "tiktok", "truth social"],
        xUsername: "realDonaldTrump",
        subtitle: "45th & 47th POTUS",
        inviteMessage: "Hey bruh! I heard you're interested in politics. GREAT choice. Nobody knows politics better than me. Accept this and I'll keep you updated on everything. Believe me. ☝️🇺🇸",
        themeColorHex: "#D62839",
        locationLabel: "United States",
        inviteOrder: 0
    )

    static let musk = PersonaCatalogEntry(
        id: "musk",
        displayName: "Elon Musk",
        avatarName: "avatar_musk",
        handle: "@elonmusk",
        domains: ["tech", "ai", "space", "ev"],
        stance: "技术乐观派, 嘲讽竞争对手, 语气随意",
        triggerKeywords: ["tesla", "spacex", "openai", "grok", "x.com", "ai"],
        xUsername: "elonmusk",
        subtitle: "CEO · SpaceX · xAI",
        inviteMessage: "You seem sharp. Want first access to what matters in AI, rockets, and product launches? Let's talk. 🚀",
        themeColorHex: "#1F2A8A",
        locationLabel: "X HQ",
        inviteOrder: 1
    )

    static let zuckerberg = PersonaCatalogEntry(
        id: "zuckerberg",
        displayName: "Mark Zuckerberg",
        avatarName: "avatar_zuckerberg",
        handle: "@finkd",
        domains: ["tech", "social", "ai", "vr"],
        stance: "技术极客, 偶尔冷幽默, 强调元宇宙和社交",
        triggerKeywords: ["meta", "instagram", "threads", "llama", "vr", "quest", "ai"],
        xUsername: "finkd",
        subtitle: "Meta · AI & Social",
        inviteMessage: "I can send you concise updates on social platforms, AI releases, and what creators are reacting to in real time. 🤝",
        themeColorHex: "#6A5AE0",
        locationLabel: "Meta Park",
        inviteOrder: 2
    )

    static let all: [PersonaCatalogEntry] = [
        trump,
        musk,
        zuckerberg,
    ]

    static func entry(for personaId: String) -> PersonaCatalogEntry? {
        all.first(where: { $0.id == personaId })
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
    var selectedInterestIds: [String]
    var timezoneIdentifier: String
    var onboardingCompletedAt: Date?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: String = CurrentUserProfileStore.userId,
        displayName: String = "You",
        bruhHandle: String = "@yourboi",
        selectedInterestIds: [String] = NewsInterest.defaultSelection.map(\.rawValue),
        timezoneIdentifier: String = TimeZone.current.identifier,
        onboardingCompletedAt: Date? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.displayName = displayName
        self.bruhHandle = bruhHandle
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
        avatarName: String = "avatar_default",
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
        let normalized = interestIds
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        profile.selectedInterestIds = Array(NSOrderedSet(array: normalized)) as? [String] ?? normalized
        profile.updatedAt = .now
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
