import Foundation

enum ContentGraphSelectors {
    static func acceptedPersonaIds(from contacts: [Contact]) -> Set<String> {
        Set(
            contacts
                .filter { $0.relationshipStatusValue == .accepted }
                .compactMap(\.linkedPersonaId)
        )
    }

    static func visibleMessageDeliveries(
        from deliveries: [ContentDelivery],
        contacts: [Contact]
    ) -> [ContentDelivery] {
        let acceptedPersonaIds = acceptedPersonaIds(from: contacts)
        return deliveries.filter { delivery in
            delivery.channelValue == .message
                && delivery.isVisible
                && acceptedPersonaIds.contains(delivery.personaId ?? "")
        }
    }

    static func visibleAlbumDeliveries(
        from deliveries: [ContentDelivery],
        contacts: [Contact]
    ) -> [ContentDelivery] {
        let acceptedPersonaIds = acceptedPersonaIds(from: contacts)
        return deliveries.filter { delivery in
            delivery.channelValue == .album
                && delivery.isVisible
                && !(delivery.imageUrl?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
                && acceptedPersonaIds.contains(delivery.personaId ?? "")
        }
    }
}
