import Foundation
import SwiftData

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
        "liu_jingkang": "+86 755 5555 0136",
        "luo_yonghao": "+86 10 5555 0127",
        "justin_sun": "+852 5550 0133",
        "kim_kardashian": "+1 323 555 0199",
        "papi": "+86 21 5555 0126",
        "kobe_bryant": "+1 213 555 0824",
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
        "liu_jingkang": "jk@insta360.com",
        "luo_yonghao": "laoluo@smartisan.com",
        "justin_sun": "justin@tron.network",
        "kim_kardashian": "kim@skims.com",
        "papi": "papi@papitube.com",
        "kobe_bryant": "kobe@mamba.local",
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
