import Foundation
import SwiftData

enum SystemContactSeedWriter {
    @MainActor
    static func sync(into context: ModelContext) {
        let personas: [Persona] = (try? context.fetch(FetchDescriptor<Persona>())) ?? []
        let contacts: [Contact] = (try? context.fetch(FetchDescriptor<Contact>())) ?? []
        let deletedPersonaIds = SystemContactUserStateStore.deletedPersonaIds()
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
            .filter { SystemInvitePersonaAllowlist.ids.contains($0.key) }
        let firstPendingPersonaId = inviteOrderMap
            .filter { !deletedPersonaIds.contains($0.key) }
            .sorted(by: { $0.value < $1.value })
            .first?.key

        for persona in personas.sorted(by: { (inviteOrderMap[$0.id] ?? $0.inviteOrder) < (inviteOrderMap[$1.id] ?? $1.inviteOrder) }) {
            if deletedPersonaIds.contains(persona.id) {
                if let existing = existingByPersonaId[persona.id] {
                    context.delete(existing)
                }
                continue
            }

            let effectiveInviteOrder = inviteOrderMap[persona.id] ?? persona.inviteOrder
            let resolvedStatus: ContactRelationshipStatus

            if let contact = existingByPersonaId[persona.id] {
                let previousStatus = contact.relationshipStatusValue

                if previousStatus == .custom || previousStatus == .accepted {
                    resolvedStatus = .accepted
                } else if previousStatus == .ignored {
                    resolvedStatus = .ignored
                } else {
                    resolvedStatus = resolvedInviteStatus(
                        for: persona.id,
                        legacyInviteState: legacyInviteState,
                        engagedPersonaIds: engagedPersonaIds,
                        firstPendingPersonaId: firstPendingPersonaId
                    )
                }

                SystemContactUserStateStore.migrateLegacyProfileOverrideIfNeeded(from: contact)

                contact.name = persona.displayName
                contact.phoneNumber = defaultPhoneNumber(for: persona.id)
                contact.email = defaultEmail(for: persona.id)
                contact.avatarName = persona.avatarName
                contact.themeColorHex = persona.themeColorHex
                contact.locationLabel = persona.locationLabel
                contact.inviteOrder = effectiveInviteOrder

                if resolvedStatus == .accepted {
                    contact.relationshipStatusValue = .accepted
                    contact.acceptedAt = contact.acceptedAt ?? contact.updatedAt
                } else if resolvedStatus == .ignored {
                    contact.relationshipStatusValue = .ignored
                    contact.ignoredAt = contact.ignoredAt ?? contact.updatedAt
                } else {
                    contact.relationshipStatusValue = resolvedStatus
                    if resolvedStatus == .accepted {
                        contact.acceptedAt = contact.acceptedAt ?? Date.now
                    }
                    if resolvedStatus == .ignored {
                        contact.ignoredAt = contact.ignoredAt ?? Date.now
                    }
                }

                if let profileOverride = SystemContactUserStateStore.profileOverride(for: persona.id) {
                    SystemContactUserStateStore.applyProfileOverride(profileOverride, to: contact)
                }

                contact.updatedAt = Date.now
                continue
            }

            resolvedStatus = resolvedInviteStatus(
                for: persona.id,
                legacyInviteState: legacyInviteState,
                engagedPersonaIds: engagedPersonaIds,
                firstPendingPersonaId: firstPendingPersonaId
            )
            let contact = Contact(
                linkedPersonaId: persona.id,
                name: persona.displayName,
                phoneNumber: defaultPhoneNumber(for: persona.id),
                email: defaultEmail(for: persona.id),
                avatarName: persona.avatarName,
                themeColorHex: persona.themeColorHex,
                locationLabel: persona.locationLabel,
                isFavorite: resolvedStatus == .accepted,
                relationshipStatus: resolvedStatus.rawValue,
                inviteOrder: effectiveInviteOrder,
                acceptedAt: resolvedStatus == .accepted ? .now : nil,
                ignoredAt: resolvedStatus == .ignored ? .now : nil,
                affinityScore: resolvedStatus == .accepted ? 0.72 : 0.5
            )

            if let profileOverride = SystemContactUserStateStore.profileOverride(for: persona.id) {
                SystemContactUserStateStore.applyProfileOverride(profileOverride, to: contact)
            }

            context.insert(contact)
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
        let activeDemoPersonaIds = contacts
            .compactMap(\.linkedPersonaId)
            .filter { demoOrder[$0] != nil }
            .sorted { (demoOrder[$0] ?? .max) < (demoOrder[$1] ?? .max) }
        let firstActiveDemoPersonaId = activeDemoPersonaIds.first

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
        guard let firstActiveDemoPersonaId else { return }

        for contact in contacts {
            guard let personaId = contact.linkedPersonaId, let order = demoOrder[personaId] else { continue }
            contact.inviteOrder = order
        }

        // Set the first available demo persona to pending, everyone else to locked.
        for contact in contacts {
            guard let personaId = contact.linkedPersonaId else { continue }
            if personaId == firstActiveDemoPersonaId {
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
