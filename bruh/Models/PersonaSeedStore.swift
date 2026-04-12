import Foundation
import SwiftData

@MainActor
func seedPersonas(into context: ModelContext) {
    PersonaCatalogSeedWriter.sync(into: context)
    PersonaRetirementCleaner.purge(into: context)
}

@MainActor
func purgeRetiredPersonaData(into context: ModelContext) {
    PersonaRetirementCleaner.purge(into: context)
}

@MainActor
func seedSystemContacts(into context: ModelContext) {
    SystemContactSeedWriter.sync(into: context)
}

@MainActor
func forceDemoInviteOrder(into context: ModelContext) {
    SystemContactSeedWriter.forceDemoInviteOrder(into: context)
}
