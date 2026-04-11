import SwiftData

@MainActor
func seedPengyouMoments(into context: ModelContext) {
    PengyouMomentSeedWriter.sync(PengyouMomentSeedCatalog.seeds, into: context)
}
