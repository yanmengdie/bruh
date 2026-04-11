import Foundation
import SwiftData

@MainActor
func seedCurrentUserProfile(into context: ModelContext) {
    _ = CurrentUserProfileStore.fetchOrCreate(in: context)
}

@MainActor
func syncContentGraph(into context: ModelContext) {
    ContentGraphStore.backfill(in: context)

    if context.hasChanges {
        try? context.save()
    }
}
