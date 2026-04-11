import Foundation
import SwiftData

enum CurrentUserProfileStore {
    static let userId = "viewer"
    static let avatarImageDataKey = "viewer.avatarImageData"

    @MainActor
    static func fetchOrCreate(in context: ModelContext) -> UserProfile {
        var descriptor = FetchDescriptor<UserProfile>(
            predicate: #Predicate { $0.id == userId }
        )
        descriptor.fetchLimit = 1

        if let existing = try? context.fetch(descriptor).first {
            migrateLegacyPreferencesIfNeeded(profile: existing)
            return existing
        }

        let profile = UserProfile(
            displayName: "You",
            bruhHandle: "@yourboi",
            selectedInterestIds: legacyOrDefaultInterests()
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
        in context: ModelContext
    ) {
        let profile = fetchOrCreate(in: context)
        let trimmedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        profile.displayName = trimmedName.isEmpty ? "You" : trimmedName
        profile.selectedInterestIds = normalizedInterestIds(selectedInterestIds)
        if let avatarImageData {
            profile.avatarImageData = avatarImageData
        }
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

        let profile = fetchOrCreate(in: context)
        profile.displayName = trimmed
        profile.bruhHandle = bruhHandle(from: trimmed)
        profile.onboardingCompletedAt = profile.onboardingCompletedAt ?? .now
        profile.updatedAt = .now

        if let avatarImageData, !avatarImageData.isEmpty {
            userDefaults.set(avatarImageData, forKey: avatarImageDataKey)
        }

        if context.hasChanges {
            try? context.save()
        }
    }

    static func avatarImageData(userDefaults: UserDefaults = .standard) -> Data? {
        userDefaults.data(forKey: avatarImageDataKey)
    }

    @MainActor
    private static func migrateLegacyPreferencesIfNeeded(profile: UserProfile) {
        guard profile.selectedInterestIds.isEmpty else { return }
        profile.selectedInterestIds = legacyOrDefaultInterests()
        profile.updatedAt = .now
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
