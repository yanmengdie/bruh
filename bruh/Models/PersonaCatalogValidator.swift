import Foundation

enum PersonaCatalogValidationError: LocalizedError {
    case invalid(String)

    var errorDescription: String? {
        switch self {
        case .invalid(let message):
            return message
        }
    }
}

enum PersonaCatalogValidator {
    private static let allowedPrimaryLanguages: Set<String> = ["en", "zh"]
    private static let themeColorPattern = /^#[0-9A-Fa-f]{6}$/

    static func validate(_ entries: [PersonaCatalogResourceEntry]) throws -> [PersonaCatalogResourceEntry] {
        guard !entries.isEmpty else {
            throw PersonaCatalogValidationError.invalid("SharedPersonas.json must contain at least one persona.")
        }

        var seenIds = Set<String>()

        for entry in entries {
            try requireNonEmpty(entry.id, path: "\(entry.id).id")
            if !seenIds.insert(entry.id).inserted {
                throw PersonaCatalogValidationError.invalid("Duplicate persona id: \(entry.id)")
            }

            try requireNonEmpty(entry.displayName, path: "\(entry.id).displayName")
            try requireNonEmpty(entry.avatarName, path: "\(entry.id).avatarName")
            let handle = try requireNonEmpty(entry.handle, path: "\(entry.id).handle")
            guard handle.hasPrefix("@") else {
                throw PersonaCatalogValidationError.invalid("\(entry.id).handle must start with @.")
            }

            try requireStringArray(entry.domains, path: "\(entry.id).domains")
            try requireStringArray(entry.leadInterestIds, path: "\(entry.id).leadInterestIds")
            try requireNonEmpty(entry.stance, path: "\(entry.id).stance")
            try requireStringArray(entry.triggerKeywords, path: "\(entry.id).triggerKeywords")
            try requireStringArray(entry.entityKeywords, path: "\(entry.id).entityKeywords")
            try requireNonEmpty(entry.subtitle, path: "\(entry.id).subtitle")
            try requireNonEmpty(entry.inviteMessage, path: "\(entry.id).inviteMessage")
            let themeColorHex = try requireNonEmpty(entry.themeColorHex, path: "\(entry.id).themeColorHex")
            guard themeColorHex.wholeMatch(of: themeColorPattern) != nil else {
                throw PersonaCatalogValidationError.invalid("\(entry.id).themeColorHex must be a 6-digit hex color.")
            }

            try requireNonEmpty(entry.locationLabel, path: "\(entry.id).locationLabel")
            guard entry.baseInviteOrder >= 0 else {
                throw PersonaCatalogValidationError.invalid("\(entry.id).baseInviteOrder must be non-negative.")
            }

            let primaryLanguage = try requireNonEmpty(entry.primaryLanguage, path: "\(entry.id).primaryLanguage")
            guard allowedPrimaryLanguages.contains(primaryLanguage) else {
                throw PersonaCatalogValidationError.invalid("\(entry.id).primaryLanguage must be one of \(allowedPrimaryLanguages.sorted()).")
            }

            try requireNonEmpty(entry.friendGreeting, path: "\(entry.id).friendGreeting")
            try requireStringArray(entry.aliases, path: "\(entry.id).aliases")
            try requireNonEmpty(entry.defaultVoiceSpeakerId, path: "\(entry.id).defaultVoiceSpeakerId")
            try requireNonEmpty(entry.defaultVoiceLabel, path: "\(entry.id).defaultVoiceLabel")
            let socialCircleIds = try requireStringArray(entry.socialCircleIds, path: "\(entry.id).socialCircleIds")

            try validatePlatformAccounts(entry.platformAccounts, path: "\(entry.id).platformAccounts")
            for (relatedId, hint) in entry.relationshipHints {
                try requireNonEmpty(hint, path: "\(entry.id).relationshipHints.\(relatedId)")
                guard socialCircleIds.contains(relatedId) else {
                    throw PersonaCatalogValidationError.invalid("\(entry.id).relationshipHints.\(relatedId) must reference socialCircleIds.")
                }
            }
        }

        return entries
    }

    @discardableResult
    private static func requireNonEmpty(_ value: String, path: String) throws -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw PersonaCatalogValidationError.invalid("\(path) must be non-empty.")
        }
        return trimmed
    }

    @discardableResult
    private static func requireStringArray(_ values: [String], path: String) throws -> [String] {
        var seen = Set<String>()
        for value in values {
            let trimmed = try requireNonEmpty(value, path: path)
            guard seen.insert(trimmed).inserted else {
                throw PersonaCatalogValidationError.invalid("\(path) must not contain duplicates.")
            }
        }
        return values
    }

    private static func validatePlatformAccounts(_ accounts: [PersonaPlatformAccount], path: String) throws {
        var primaryPlatforms = Set<String>()

        for account in accounts {
            let platform = try requireNonEmpty(account.platform, path: "\(path).platform")
            _ = try requireNonEmpty(account.handle, path: "\(path).handle")

            if let profileUrl = account.profileUrl, !profileUrl.isEmpty {
                _ = try requireNonEmpty(profileUrl, path: "\(path).profileUrl")
            }

            if account.isPrimary {
                guard primaryPlatforms.insert(platform.lowercased()).inserted else {
                    throw PersonaCatalogValidationError.invalid("\(path) must not define multiple primary accounts for \(platform).")
                }
            }
        }
    }
}
