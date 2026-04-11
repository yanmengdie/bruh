import Foundation

enum PersonaCatalogInviteRanker {
    static func inviteOrderMap(for selectedInterestIds: [String], entries: [PersonaCatalogEntry]) -> [String: Int] {
        Dictionary(
            uniqueKeysWithValues: prioritizedEntries(for: selectedInterestIds, entries: entries)
                .enumerated()
                .map { ($0.element.id, $0.offset) }
        )
    }

    private static func prioritizedEntries(
        for selectedInterestIds: [String],
        entries: [PersonaCatalogEntry]
    ) -> [PersonaCatalogEntry] {
        let normalizedInterests = orderedUnique(selectedInterestIds)

        return entries.sorted { left, right in
            let leftScore = invitePriorityScore(for: left, selectedInterestIds: normalizedInterests, entries: entries)
            let rightScore = invitePriorityScore(for: right, selectedInterestIds: normalizedInterests, entries: entries)

            if leftScore != rightScore {
                return leftScore > rightScore
            }

            return left.inviteOrder < right.inviteOrder
        }
    }

    private static func invitePriorityScore(
        for entry: PersonaCatalogEntry,
        selectedInterestIds: [String],
        entries: [PersonaCatalogEntry]
    ) -> Int {
        guard !selectedInterestIds.isEmpty else { return 0 }

        let overlap = selectedInterestIds.filter(entry.domains.contains)
        let overlapScore = overlap.count * 100
        let orderedBonus = overlap.enumerated().reduce(0) { partial, element in
            partial + max(0, 60 - element.offset * 15)
        }

        let primaryBoost: Int
        if let primaryInterestId = selectedInterestIds.first {
            if primaryLeadPersonaId(for: primaryInterestId, entries: entries) == entry.id {
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

    private static func primaryLeadPersonaId(
        for interestId: String,
        entries: [PersonaCatalogEntry]
    ) -> String? {
        entries
            .filter { $0.leadInterestIds.contains(interestId) }
            .min(by: { $0.inviteOrder < $1.inviteOrder })?
            .id ??
        entries
            .filter { $0.domains.contains(interestId) }
            .min(by: { $0.inviteOrder < $1.inviteOrder })?
            .id
    }

    private static func orderedUnique<T: Hashable>(_ values: [T]) -> [T] {
        var seen = Set<T>()
        var result: [T] = []
        for value in values where seen.insert(value).inserted {
            result.append(value)
        }
        return result
    }
}
