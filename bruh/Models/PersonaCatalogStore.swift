import Foundation

struct PersonaCatalogResourceEntry: Decodable {
    let id: String
    let displayName: String
    let avatarName: String
    let handle: String
    let domains: [String]
    let stance: String
    let triggerKeywords: [String]
    let entityKeywords: [String]
    let leadInterestIds: [String]
    let subtitle: String
    let inviteMessage: String
    let themeColorHex: String
    let locationLabel: String
    let baseInviteOrder: Int
    let primaryLanguage: String
    let friendGreeting: String
    let aliases: [String]
    let platformAccounts: [PersonaPlatformAccount]
    let defaultVoiceSpeakerId: String
    let defaultVoiceLabel: String
    let socialCircleIds: [String]
    let relationshipHints: [String: String]

    func makeCatalogEntry() -> PersonaCatalogEntry {
        let primaryXAccount = platformAccounts.first(where: { $0.platform == "x" && $0.isActive })?.handle ?? ""
        return PersonaCatalogEntry(
            id: id,
            displayName: displayName,
            avatarName: avatarName,
            handle: handle,
            domains: domains,
            stance: stance,
            triggerKeywords: triggerKeywords,
            leadInterestIds: leadInterestIds,
            xUsername: primaryXAccount,
            subtitle: subtitle,
            inviteMessage: inviteMessage,
            themeColorHex: themeColorHex,
            locationLabel: locationLabel,
            inviteOrder: baseInviteOrder,
            aliases: aliases,
            entityKeywords: entityKeywords,
            primaryLanguage: primaryLanguage,
            friendGreeting: friendGreeting,
            defaultVoiceSpeakerId: defaultVoiceSpeakerId,
            defaultVoiceLabel: defaultVoiceLabel,
            socialCircleIds: socialCircleIds,
            relationshipHints: relationshipHints,
            platformAccounts: platformAccounts
        )
    }
}

private final class PersonaCatalogBundleMarker: NSObject {}

enum PersonaCatalogStore {
    static let loadedEntries: [PersonaCatalogEntry] = loadEntries()

    static func entry(for personaId: String) -> PersonaCatalogEntry? {
        loadedEntries.first(where: { $0.id == personaId })
    }

    static func requiredEntry(for personaId: String) -> PersonaCatalogEntry {
        guard let entry = entry(for: personaId) else {
            fatalError("Missing persona catalog entry for \(personaId)")
        }
        return entry
    }

    private static func loadEntries() -> [PersonaCatalogEntry] {
        let decoder = JSONDecoder()
        for bundle in candidateBundles() {
            guard let url = bundle.url(forResource: "SharedPersonas", withExtension: "json"),
                  let data = try? Data(contentsOf: url),
                  let decoded = try? decoder.decode([PersonaCatalogResourceEntry].self, from: data) else {
                continue
            }

            do {
                return try PersonaCatalogValidator.validate(decoded)
                    .map { $0.makeCatalogEntry() }
                    .sorted { $0.inviteOrder < $1.inviteOrder }
            } catch {
                preconditionFailure("SharedPersonas.json validation failed: \(error.localizedDescription)")
            }
        }

        assertionFailure("SharedPersonas.json could not be loaded from the app bundle.")
        return []
    }

    private static func candidateBundles() -> [Bundle] {
        let bundles = [
            Bundle.main,
            Bundle(for: PersonaCatalogBundleMarker.self),
        ]

        var seen = Set<String>()
        var result: [Bundle] = []
        for bundle in bundles where seen.insert(bundle.bundlePath).inserted {
            result.append(bundle)
        }
        return result
    }
}
