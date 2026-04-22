import Foundation
import SwiftData

struct SystemContactProfileOverride: Codable {
    var name: String?
    var phoneNumber: String?
    var email: String?

    var hasValues: Bool {
        name != nil || phoneNumber != nil || email != nil
    }
}

enum SystemContactUserStateStore {
    private static let deletedPersonaIdsKey = "systemContacts.deletedPersonaIds"
    private static let profileOverridesKey = "systemContacts.profileOverrides"

    static func deletedPersonaIds(userDefaults: UserDefaults = .standard) -> Set<String> {
        let scopedDefaults = ScopedUserDefaultsStore(userDefaults: userDefaults)

        guard let data = scopedDefaults.data(for: deletedPersonaIdsKey),
              let decoded = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }

        return Set(decoded)
    }

    static func markDeleted(_ personaId: String, userDefaults: UserDefaults = .standard) {
        var ids = deletedPersonaIds(userDefaults: userDefaults)
        ids.insert(personaId)
        saveDeletedPersonaIds(ids, userDefaults: userDefaults)
    }

    static func clearDeleted(_ personaId: String, userDefaults: UserDefaults = .standard) {
        var ids = deletedPersonaIds(userDefaults: userDefaults)
        ids.remove(personaId)
        saveDeletedPersonaIds(ids, userDefaults: userDefaults)
    }

    static func profileOverride(
        for personaId: String,
        userDefaults: UserDefaults = .standard
    ) -> SystemContactProfileOverride? {
        profileOverrides(userDefaults: userDefaults)[personaId]
    }

    static func saveProfileOverride(
        _ override: SystemContactProfileOverride,
        for personaId: String,
        userDefaults: UserDefaults = .standard
    ) {
        var overrides = profileOverrides(userDefaults: userDefaults)
        if override.hasValues {
            overrides[personaId] = override
        } else {
            overrides.removeValue(forKey: personaId)
        }
        saveProfileOverrides(overrides, userDefaults: userDefaults)
    }

    static func clearProfileOverride(
        for personaId: String,
        userDefaults: UserDefaults = .standard
    ) {
        var overrides = profileOverrides(userDefaults: userDefaults)
        overrides.removeValue(forKey: personaId)
        saveProfileOverrides(overrides, userDefaults: userDefaults)
    }

    static func makeProfileOverride(
        personaId: String,
        name: String,
        phoneNumber: String,
        email: String
    ) -> SystemContactProfileOverride? {
        let normalizedName = normalize(name)
        let normalizedPhoneNumber = normalize(phoneNumber)
        let normalizedEmail = normalize(email)
        let defaultName = PersonaCatalog.entry(for: personaId)?.displayName ?? personaId
        let defaultPhoneNumberValue = normalize(defaultPhoneNumber(for: personaId))
        let defaultEmailValue = normalize(defaultEmail(for: personaId))

        let override = SystemContactProfileOverride(
            name: normalizedName == defaultName ? nil : normalizedName,
            phoneNumber: normalizedPhoneNumber == defaultPhoneNumberValue ? nil : normalizedPhoneNumber,
            email: normalizedEmail == defaultEmailValue ? nil : normalizedEmail
        )

        return override.hasValues ? override : nil
    }

    static func migrateLegacyProfileOverrideIfNeeded(
        from contact: Contact,
        userDefaults: UserDefaults = .standard
    ) {
        guard let personaId = contact.linkedPersonaId else { return }
        guard contact.relationshipStatusValue == .custom else { return }
        guard profileOverride(for: personaId, userDefaults: userDefaults) == nil else { return }

        let baselineOverride = makeProfileOverride(
            personaId: personaId,
            name: contact.name,
            phoneNumber: contact.phoneNumber,
            email: contact.email
        )

        if let baselineOverride {
            saveProfileOverride(baselineOverride, for: personaId, userDefaults: userDefaults)
        } else {
            clearProfileOverride(for: personaId, userDefaults: userDefaults)
        }
    }

    static func applyProfileOverride(
        _ override: SystemContactProfileOverride,
        to contact: Contact
    ) {
        if let name = override.name {
            contact.name = name
        }
        if let phoneNumber = override.phoneNumber {
            contact.phoneNumber = phoneNumber
        }
        if let email = override.email {
            contact.email = email
        }
    }

    private static func profileOverrides(
        userDefaults: UserDefaults = .standard
    ) -> [String: SystemContactProfileOverride] {
        let scopedDefaults = ScopedUserDefaultsStore(userDefaults: userDefaults)

        guard let data = scopedDefaults.data(for: profileOverridesKey),
              let decoded = try? JSONDecoder().decode([String: SystemContactProfileOverride].self, from: data) else {
            return [:]
        }

        return decoded
    }

    private static func saveDeletedPersonaIds(
        _ ids: Set<String>,
        userDefaults: UserDefaults = .standard
    ) {
        let scopedDefaults = ScopedUserDefaultsStore(userDefaults: userDefaults)
        let sortedIds = ids.sorted()
        let encoded = try? JSONEncoder().encode(sortedIds)
        scopedDefaults.set(encoded, for: deletedPersonaIdsKey)
    }

    private static func saveProfileOverrides(
        _ overrides: [String: SystemContactProfileOverride],
        userDefaults: UserDefaults = .standard
    ) {
        let scopedDefaults = ScopedUserDefaultsStore(userDefaults: userDefaults)
        let encoded = try? JSONEncoder().encode(overrides)
        scopedDefaults.set(encoded, for: profileOverridesKey)
    }

    private static func normalize(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

@MainActor
func fetchEngagedPersonaIds(from context: ModelContext) -> Set<String> {
    let threads: [MessageThread] = (try? context.fetch(FetchDescriptor<MessageThread>())) ?? []
    let messages: [PersonaMessage] = (try? context.fetch(FetchDescriptor<PersonaMessage>())) ?? []
    let threadPersonaIds = threads.map(\.personaId)
    let messagePersonaIds = messages.map(\.personaId)
    return Set(threadPersonaIds + messagePersonaIds)
}

func defaultPhoneNumber(for personaId: String) -> String {
    let directory: [String: String] = [
        "musk": "+1 310 555 0142",
        "trump": "+1 561 555 0145",
        "sam_altman": "+1 415 555 0112",
        "zhang_peng": "+86 10 5555 0188",
        "lei_jun": "+86 10 5555 0168",
        "luo_yonghao": "+86 10 5555 0127",
        "justin_sun": "+852 5550 0133",
        "kim_kardashian": "+1 323 555 0199",
        "papi": "+86 21 5555 0126",
        "cristiano_ronaldo": "+351 21 555 0107",
    ]

    return directory[personaId] ?? "+1 555 0100"
}

func defaultEmail(for personaId: String) -> String {
    let directory: [String: String] = [
        "musk": "elon@x.ai",
        "trump": "donald@truthsocial.com",
        "sam_altman": "sam@openai.com",
        "zhang_peng": "peng@geekpark.net",
        "lei_jun": "jun@xiaomi.com",
        "luo_yonghao": "laoluo@smartisan.com",
        "justin_sun": "justin@tron.network",
        "kim_kardashian": "kim@skims.com",
        "papi": "papi@papitube.com",
        "cristiano_ronaldo": "cr7@cr7.com",
    ]

    return directory[personaId] ?? "bruh@contact.local"
}

func legacyInviteStateByPersonaId(userDefaults: UserDefaults = .standard) -> [String: ContactRelationshipStatus] {
    let scopedDefaults = ScopedUserDefaultsStore(userDefaults: userDefaults)
    let trumpAccepted = scopedDefaults.bool(for: "invite_trump_accepted")
    let trumpIgnored = scopedDefaults.bool(for: "invite_trump_ignored")
    let muskAccepted = scopedDefaults.bool(for: "invite_musk_accepted")
    let muskIgnored = scopedDefaults.bool(for: "invite_musk_ignored")
    let muskUnlocked = scopedDefaults.bool(for: "invite_musk_unlocked")

    var result: [String: ContactRelationshipStatus] = [:]
    result["trump"] = trumpAccepted ? .accepted : (trumpIgnored ? .ignored : .pending)
    result["musk"] = muskAccepted ? .accepted : (muskIgnored ? .ignored : (muskUnlocked ? .pending : .locked))
    return result
}

func resolvedInviteStatus(
    for personaId: String,
    legacyInviteState: [String: ContactRelationshipStatus],
    engagedPersonaIds: Set<String>,
    firstPendingPersonaId: String?
) -> ContactRelationshipStatus {
    if engagedPersonaIds.contains(personaId) {
        return .accepted
    }

    if let status = legacyInviteState[personaId] {
        return status
    }

    if firstPendingPersonaId == personaId {
        return .pending
    }

    return .locked
}

@MainActor
func normalizeInviteFrontier(in context: ModelContext) {
    let contacts: [Contact] = (try? context.fetch(FetchDescriptor<Contact>())) ?? []
    let personaContacts = contacts
        .filter { $0.linkedPersonaId != nil }
        .sorted { ($0.inviteOrder ?? 999) < ($1.inviteOrder ?? 999) }

    var frontierLocked = false
    for contact in personaContacts {
        switch contact.relationshipStatusValue {
        case .accepted, .ignored:
            continue
        case .pending:
            if frontierLocked {
                contact.relationshipStatusValue = .locked
            } else {
                frontierLocked = true
            }
        case .locked:
            if !frontierLocked {
                contact.relationshipStatusValue = .pending
                frontierLocked = true
            }
        case .custom:
            continue
        }
    }
}
