import Foundation
import SwiftData

@Model
final class Persona {
    @Attribute(.unique) var id: String
    var displayName: String
    var avatarName: String   // asset name in Assets.xcassets
    var handle: String       // e.g. "@elonmusk"
    var domains: [String]    // e.g. ["tech","ai","space"]
    var stance: String       // personality description
    var triggerKeywords: [String]
    var xUsername: String    // actual X handle for API

    init(
        id: String,
        displayName: String,
        avatarName: String,
        handle: String,
        domains: [String],
        stance: String,
        triggerKeywords: [String],
        xUsername: String
    ) {
        self.id = id
        self.displayName = displayName
        self.avatarName = avatarName
        self.handle = handle
        self.domains = domains
        self.stance = stance
        self.triggerKeywords = triggerKeywords
        self.xUsername = xUsername
    }
}

extension Persona {
    static let trump = Persona(
        id: "trump",
        displayName: "Donald Trump",
        avatarName: "avatar_trump",
        handle: "@realDonaldTrump",
        domains: ["politics", "finance", "trade"],
        stance: "美国优先, 反建制, 自我吹嘘, 攻击对手",
        triggerKeywords: ["tariff", "china", "trade", "election", "tiktok", "truth social"],
        xUsername: "realDonaldTrump"
    )

    static let musk = Persona(
        id: "musk",
        displayName: "马期克",
        avatarName: "Avatar_ Elon",
        handle: "@elonmusk",
        domains: ["tech", "ai", "space", "ev"],
        stance: "技术乐观派, 嘲讽竞争对手, 语气随意",
        triggerKeywords: ["tesla", "spacex", "openai", "grok", "x.com", "ai"],
        xUsername: "elonmusk"
    )

    static let zuckerberg = Persona(
        id: "zuckerberg",
        displayName: "Mark Zuckerberg",
        avatarName: "avatar_zuckerberg",
        handle: "@finkd",
        domains: ["tech", "social", "ai", "vr"],
        stance: "技术极客, 偶尔冷幽默, 强调元宇宙和社交",
        triggerKeywords: ["meta", "instagram", "threads", "llama", "vr", "quest", "ai"],
        xUsername: "finkd"
    )

    static let all: [Persona] = [.trump, .musk, .zuckerberg]
}

@Model
final class Contact {
    @Attribute(.unique) var id: UUID
    var linkedPersonaId: String?
    var name: String
    var phoneNumber: String
    var email: String
    var avatarName: String
    var themeColorHex: String
    var locationLabel: String
    var isFavorite: Bool
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        linkedPersonaId: String? = nil,
        name: String,
        phoneNumber: String,
        email: String = "",
        avatarName: String = "avatar_default",
        themeColorHex: String = "#3B82F6",
        locationLabel: String = "",
        isFavorite: Bool = false,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.linkedPersonaId = linkedPersonaId
        self.name = name
        self.phoneNumber = phoneNumber
        self.email = email
        self.avatarName = avatarName
        self.themeColorHex = themeColorHex
        self.locationLabel = locationLabel
        self.isFavorite = isFavorite
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
