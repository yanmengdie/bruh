import Foundation
import SwiftData

enum PengyouMomentSeedWriter {
    @MainActor
    static func sync(_ seeds: [PengyouMomentSeed], into context: ModelContext) {
        let validIds = Set(seeds.map(\.id))
        let moments: [PengyouMoment] = (try? context.fetch(FetchDescriptor<PengyouMoment>())) ?? []
        let existingById = Dictionary(uniqueKeysWithValues: moments.map { ($0.id, $0) })

        for moment in moments where moment.id.hasPrefix("pengyou:") && !validIds.contains(moment.id) {
            context.delete(moment)
        }

        for seed in seeds {
            if let moment = existingById[seed.id] {
                apply(seed, to: moment)
            } else {
                context.insert(makeMoment(from: seed))
            }
        }

        if context.hasChanges {
            try? context.save()
        }
    }

    @MainActor
    private static func apply(_ seed: PengyouMomentSeed, to moment: PengyouMoment) {
        moment.personaId = seed.personaId
        moment.displayName = seed.displayName
        moment.handle = seed.handle
        moment.avatarName = seed.avatarName
        moment.locationLabel = seed.locationLabel
        moment.sourceType = seed.sourceType
        moment.exportedAt = seed.exportedAt
        moment.postId = seed.postId
        moment.content = seed.content
        moment.sourceUrl = PengyouMomentSeedSupport.normalizedValue(seed.sourceUrl)
        moment.mediaUrls = PengyouMomentSeedSupport.normalizedMediaURLs(seed.mediaUrls)
        moment.videoUrl = PengyouMomentSeedSupport.normalizedValue(seed.videoUrl)
        moment.publishedAt = seed.publishedAt
        moment.updatedAt = .now
    }

    private static func makeMoment(from seed: PengyouMomentSeed) -> PengyouMoment {
        PengyouMoment(
            id: seed.id,
            personaId: seed.personaId,
            displayName: seed.displayName,
            handle: seed.handle,
            avatarName: seed.avatarName,
            locationLabel: seed.locationLabel,
            sourceType: seed.sourceType,
            exportedAt: seed.exportedAt,
            postId: seed.postId,
            content: seed.content,
            sourceUrl: PengyouMomentSeedSupport.normalizedValue(seed.sourceUrl),
            mediaUrls: PengyouMomentSeedSupport.normalizedMediaURLs(seed.mediaUrls),
            videoUrl: PengyouMomentSeedSupport.normalizedValue(seed.videoUrl),
            publishedAt: seed.publishedAt,
            createdAt: .now,
            updatedAt: .now
        )
    }
}
