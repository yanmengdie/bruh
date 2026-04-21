import Foundation

struct PersonaPlatformAccount: Codable, Hashable {
    let platform: String
    let handle: String
    let profileUrl: String?
    let isPrimary: Bool
    let isActive: Bool
}

struct PersonaCatalogEntry {
    let id: String
    let displayName: String
    let avatarName: String
    let handle: String
    let domains: [String]
    let stance: String
    let triggerKeywords: [String]
    let leadInterestIds: [String]
    let xUsername: String
    let subtitle: String
    let inviteMessage: String
    let themeColorHex: String
    let locationLabel: String
    let inviteOrder: Int
    let aliases: [String]
    let entityKeywords: [String]
    let primaryLanguage: String
    let friendGreeting: String
    let defaultVoiceSpeakerId: String
    let defaultVoiceLabel: String
    let socialCircleIds: [String]
    let relationshipHints: [String: String]
    let platformAccounts: [PersonaPlatformAccount]

    func makePersona() -> Persona {
        Persona(
            id: id,
            displayName: displayName,
            avatarName: avatarName,
            handle: handle,
            domains: domains,
            stance: stance,
            triggerKeywords: triggerKeywords,
            xUsername: xUsername,
            subtitle: subtitle,
            inviteMessage: inviteMessage,
            themeColorHex: themeColorHex,
            locationLabel: locationLabel,
            inviteOrder: inviteOrder
        )
    }
}

enum PersonaCatalog {
    static var trump: PersonaCatalogEntry { PersonaCatalogStore.requiredEntry(for: "trump") }
    static var musk: PersonaCatalogEntry { PersonaCatalogStore.requiredEntry(for: "musk") }
    static var samAltman: PersonaCatalogEntry { PersonaCatalogStore.requiredEntry(for: "sam_altman") }
    static var zhangPeng: PersonaCatalogEntry { PersonaCatalogStore.requiredEntry(for: "zhang_peng") }
    static var leiJun: PersonaCatalogEntry { PersonaCatalogStore.requiredEntry(for: "lei_jun") }
    static var luoYonghao: PersonaCatalogEntry { PersonaCatalogStore.requiredEntry(for: "luo_yonghao") }
    static var justinSun: PersonaCatalogEntry { PersonaCatalogStore.requiredEntry(for: "justin_sun") }
    static var kimKardashian: PersonaCatalogEntry { PersonaCatalogStore.requiredEntry(for: "kim_kardashian") }
    static var papi: PersonaCatalogEntry { PersonaCatalogStore.requiredEntry(for: "papi") }
    static var kobeBryant: PersonaCatalogEntry { PersonaCatalogStore.requiredEntry(for: "kobe_bryant") }
    static var cristianoRonaldo: PersonaCatalogEntry { PersonaCatalogStore.requiredEntry(for: "cristiano_ronaldo") }

    static var all: [PersonaCatalogEntry] {
        PersonaCatalogStore.loadedEntries
    }

    static func entry(for personaId: String) -> PersonaCatalogEntry? {
        PersonaCatalogStore.entry(for: personaId)
    }

    static func friendGreeting(for personaId: String) -> String {
        entry(for: personaId)?.friendGreeting ?? "我已添加你了，直接开始聊天吧。"
    }

    static func starterMessage(for personaId: String) -> String {
        entry(for: personaId)?.friendGreeting ?? "今天你想聊什么？"
    }

    static func inviteOrderMap(for selectedInterestIds: [String]) -> [String: Int] {
        PersonaCatalogInviteRanker.inviteOrderMap(for: selectedInterestIds, entries: all)
    }
}
