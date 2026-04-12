import Foundation
import SwiftData

enum SystemContactSeedWriter {
    @MainActor
    static func sync(into context: ModelContext) {
        let personas: [Persona] = (try? context.fetch(FetchDescriptor<Persona>())) ?? []
        let contacts: [Contact] = (try? context.fetch(FetchDescriptor<Contact>())) ?? []
        let existingByPersonaId: [String: Contact] = Dictionary(
            uniqueKeysWithValues: contacts.compactMap { contact in
                guard let personaId = contact.linkedPersonaId else { return nil }
                return (personaId, contact)
            }
        )

        let engagedPersonaIds = fetchEngagedPersonaIds(from: context)
        let legacyInviteState = legacyInviteStateByPersonaId()
        let selectedInterestIds = CurrentUserProfileStore.selectedInterests(in: context)
        let inviteOrderMap = PersonaCatalog.inviteOrderMap(for: selectedInterestIds)
        let firstPendingPersonaId = inviteOrderMap.sorted(by: { $0.value < $1.value }).first?.key

        for persona in personas.sorted(by: { (inviteOrderMap[$0.id] ?? $0.inviteOrder) < (inviteOrderMap[$1.id] ?? $1.inviteOrder) }) {
            let effectiveInviteOrder = inviteOrderMap[persona.id] ?? persona.inviteOrder
            if let contact = existingByPersonaId[persona.id] {
                let previousStatus = contact.relationshipStatusValue
                contact.name = persona.displayName
                contact.phoneNumber = defaultPhoneNumber(for: persona.id)
                contact.email = defaultEmail(for: persona.id)
                contact.avatarName = persona.avatarName
                contact.themeColorHex = persona.themeColorHex
                contact.locationLabel = persona.locationLabel
                contact.inviteOrder = effectiveInviteOrder

                if previousStatus == .custom || previousStatus == .accepted {
                    contact.relationshipStatusValue = ContactRelationshipStatus.accepted
                    contact.acceptedAt = contact.acceptedAt ?? contact.updatedAt
                } else if previousStatus == .ignored {
                    contact.ignoredAt = contact.ignoredAt ?? contact.updatedAt
                } else {
                    let migratedStatus = resolvedInviteStatus(
                        for: persona.id,
                        legacyInviteState: legacyInviteState,
                        engagedPersonaIds: engagedPersonaIds,
                        firstPendingPersonaId: firstPendingPersonaId
                    )
                    contact.relationshipStatusValue = migratedStatus
                    if migratedStatus == .accepted {
                        contact.acceptedAt = contact.acceptedAt ?? Date.now
                    }
                    if migratedStatus == .ignored {
                        contact.ignoredAt = contact.ignoredAt ?? Date.now
                    }
                }

                contact.updatedAt = Date.now
                continue
            }

            let status = resolvedInviteStatus(
                for: persona.id,
                legacyInviteState: legacyInviteState,
                engagedPersonaIds: engagedPersonaIds,
                firstPendingPersonaId: firstPendingPersonaId
            )
            context.insert(
                Contact(
                    linkedPersonaId: persona.id,
                    name: persona.displayName,
                    phoneNumber: defaultPhoneNumber(for: persona.id),
                    email: defaultEmail(for: persona.id),
                    avatarName: persona.avatarName,
                    themeColorHex: persona.themeColorHex,
                    locationLabel: persona.locationLabel,
                    isFavorite: status == .accepted,
                    relationshipStatus: status.rawValue,
                    inviteOrder: effectiveInviteOrder,
                    acceptedAt: status == .accepted ? .now : nil,
                    ignoredAt: status == .ignored ? .now : nil,
                    affinityScore: status == .accepted ? 0.72 : 0.5
                )
            )
        }

        normalizeInviteFrontier(in: context)

        if context.hasChanges {
            try? context.save()
        }
    }

    @MainActor
    static func forceDemoInviteOrder(into context: ModelContext) {
        let contacts: [Contact] = (try? context.fetch(FetchDescriptor<Contact>())) ?? []
        let demoOrder: [String: Int] = ["trump": 0, "musk": 1, "sam_altman": 2]

        // Once the demo invite flow has progressed, keep the user's current frontier intact.
        let hasDemoProgress = contacts.contains { contact in
            guard let personaId = contact.linkedPersonaId,
                  demoOrder[personaId] != nil else {
                return false
            }

            switch contact.relationshipStatusValue {
            case .accepted, .ignored:
                return true
            case .pending, .locked, .custom:
                return false
            }
        }
        guard !hasDemoProgress else { return }

        for contact in contacts {
            guard let personaId = contact.linkedPersonaId, let order = demoOrder[personaId] else { continue }
            contact.inviteOrder = order
        }

        // Set trump to pending, everyone else to locked (will be normalized)
        for contact in contacts {
            guard let personaId = contact.linkedPersonaId else { continue }
            if personaId == "trump" {
                contact.relationshipStatusValue = .pending
            } else if demoOrder[personaId] != nil {
                if contact.relationshipStatusValue != .accepted && contact.relationshipStatusValue != .ignored {
                    contact.relationshipStatusValue = .locked
                }
            }
        }

        if context.hasChanges {
            try? context.save()
        }
    }
}
