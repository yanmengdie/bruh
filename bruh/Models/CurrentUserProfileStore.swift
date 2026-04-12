import Foundation
import SwiftData

enum CurrentUserProfileStore {
    static let userId = "viewer"
    static let avatarImageDataKey = "viewer.avatarImageData"

    @MainActor
    static func fetchOrCreate(in context: ModelContext, userDefaults: UserDefaults = .standard) -> UserProfile {
        var descriptor = FetchDescriptor<UserProfile>(
            predicate: #Predicate { $0.id == userId }
        )
        descriptor.fetchLimit = 1

        if let existing = try? context.fetch(descriptor).first {
            migrateLegacyPreferencesIfNeeded(profile: existing, userDefaults: userDefaults)
            if context.hasChanges {
                try? context.save()
            }
            return existing
        }

        let profile = UserProfile(
            displayName: "You",
            bruhHandle: "@yourboi",
            avatarImageData: normalizedAvatarImageData(legacyAvatarImageData(userDefaults: userDefaults)),
            selectedInterestIds: legacyOrDefaultInterests(userDefaults: userDefaults)
        )
        context.insert(profile)
        if context.hasChanges {
            try? context.save()
        }
        return profile
    }

    @MainActor
    static func selectedInterests(in context: ModelContext) -> [String] {
        fetchOrCreate(in: context).selectedInterestIds
    }

    @MainActor
    static func updateSelectedInterests(_ interestIds: [String], in context: ModelContext) {
        let profile = fetchOrCreate(in: context)
        let normalized = normalizedInterestIds(interestIds)
        profile.updatedAt = .now
        profile.selectedInterestIds = normalized
        if context.hasChanges {
            try? context.save()
        }
    }

    @MainActor
    static func completeOnboarding(
        displayName: String,
        selectedInterestIds: [String],
        avatarImageData: Data? = nil,
        in context: ModelContext,
        userDefaults: UserDefaults = .standard
    ) {
        let profile = fetchOrCreate(in: context, userDefaults: userDefaults)
        let trimmedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedAvatarData = normalizedAvatarImageData(avatarImageData)
        profile.displayName = trimmedName.isEmpty ? "You" : trimmedName
        profile.selectedInterestIds = normalizedInterestIds(selectedInterestIds)
        profile.avatarImageData = normalizedAvatarData
        synchronizeAvatarImageData(normalizedAvatarData, userDefaults: userDefaults)
        profile.onboardingCompletedAt = .now
        profile.timezoneIdentifier = TimeZone.current.identifier
        profile.updatedAt = .now

        let slug = trimmedName
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined()
        if !slug.isEmpty {
            profile.bruhHandle = "@\(String(slug.prefix(18)))"
        }

        if context.hasChanges {
            try? context.save()
        }
    }

    @MainActor
    static func completeOnboardingProfile(
        displayName: String,
        avatarImageData: Data?,
        in context: ModelContext,
        userDefaults: UserDefaults = .standard
    ) {
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let profile = fetchOrCreate(in: context, userDefaults: userDefaults)
        let normalizedAvatarData = normalizedAvatarImageData(avatarImageData)
        profile.displayName = trimmed
        profile.bruhHandle = bruhHandle(from: trimmed)
        profile.onboardingCompletedAt = profile.onboardingCompletedAt ?? .now
        profile.updatedAt = .now

        profile.avatarImageData = normalizedAvatarData
        synchronizeAvatarImageData(normalizedAvatarData, userDefaults: userDefaults)

        if context.hasChanges {
            try? context.save()
        }
    }

    @MainActor
    static func updateAvatarImageData(
        _ avatarImageData: Data?,
        in context: ModelContext,
        userDefaults: UserDefaults = .standard
    ) {
        let profile = fetchOrCreate(in: context, userDefaults: userDefaults)
        let normalizedData = avatarImageData.flatMap { $0.isEmpty ? nil : $0 }

        profile.avatarImageData = normalizedData
        profile.updatedAt = .now

        synchronizeAvatarImageData(normalizedData, userDefaults: userDefaults)

        if context.hasChanges {
            try? context.save()
        }
    }

    @MainActor
    private static func migrateLegacyPreferencesIfNeeded(
        profile: UserProfile,
        userDefaults: UserDefaults = .standard
    ) {
        var didChange = false

        if profile.selectedInterestIds.isEmpty {
            profile.selectedInterestIds = legacyOrDefaultInterests(userDefaults: userDefaults)
            didChange = true
        }

        let normalizedProfileAvatarImageData = normalizedAvatarImageData(profile.avatarImageData)
        let normalizedLegacyAvatarImageData = normalizedAvatarImageData(legacyAvatarImageData(userDefaults: userDefaults))

        if normalizedProfileAvatarImageData == nil, let normalizedLegacyAvatarImageData {
            profile.avatarImageData = normalizedLegacyAvatarImageData
            didChange = true
        } else if normalizedProfileAvatarImageData != normalizedLegacyAvatarImageData {
            synchronizeAvatarImageData(normalizedProfileAvatarImageData, userDefaults: userDefaults)
        }

        if didChange {
            profile.updatedAt = .now
        }
    }

    private static func normalizedInterestIds(_ interestIds: [String]) -> [String] {
        let normalized = interestIds
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return Array(NSOrderedSet(array: normalized)) as? [String] ?? normalized
    }

    private static func legacyOrDefaultInterests(userDefaults: UserDefaults = .standard) -> [String] {
        if let onboardingRaw = userDefaults.string(forKey: OnboardingInterestStore.userDefaultsKey), !onboardingRaw.isEmpty {
            let parsed = onboardingRaw
                .split(separator: ",")
                .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            if !parsed.isEmpty {
                return Array(NSOrderedSet(array: parsed)) as? [String] ?? parsed
            }
        }

        let legacy = InterestPreferences.legacySelectedInterests(userDefaults: userDefaults)
        if !legacy.isEmpty {
            return legacy
        }

        return NewsInterest.defaultSelection.map(\.rawValue)
    }

    private static func legacyAvatarImageData(userDefaults: UserDefaults = .standard) -> Data? {
        userDefaults.data(forKey: avatarImageDataKey)
    }

    private static func normalizedAvatarImageData(_ avatarImageData: Data?) -> Data? {
        avatarImageData.flatMap { $0.isEmpty ? nil : $0 }
    }

    private static func synchronizeAvatarImageData(
        _ avatarImageData: Data?,
        userDefaults: UserDefaults = .standard
    ) {
        if let avatarImageData {
            userDefaults.set(avatarImageData, forKey: avatarImageDataKey)
        } else {
            userDefaults.removeObject(forKey: avatarImageDataKey)
        }
    }

    private static func bruhHandle(from displayName: String) -> String {
        let cleaned = displayName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "")

        if cleaned.isEmpty {
            return "@yourboi"
        }
        return "@\(cleaned)"
    }
}
