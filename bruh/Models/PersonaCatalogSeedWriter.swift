import Foundation
import SwiftData

enum PersonaCatalogSeedWriter {
    @MainActor
    static func sync(into context: ModelContext) {
        let existing: [Persona] = (try? context.fetch(FetchDescriptor<Persona>())) ?? []
        let existingById = Dictionary(uniqueKeysWithValues: existing.map { ($0.id, $0) })

        for seed in Persona.all {
            if let persona = existingById[seed.id] {
                persona.displayName = seed.displayName
                persona.avatarName = seed.avatarName
                persona.handle = seed.handle
                persona.domains = seed.domains
                persona.stance = seed.stance
                persona.triggerKeywords = seed.triggerKeywords
                persona.xUsername = seed.xUsername
                persona.subtitle = seed.subtitle
                persona.inviteMessage = seed.inviteMessage
                persona.themeColorHex = seed.themeColorHex
                persona.locationLabel = seed.locationLabel
                persona.inviteOrder = seed.inviteOrder
            } else {
                context.insert(seed)
            }
        }

        if context.hasChanges {
            try? context.save()
        }
    }
}
