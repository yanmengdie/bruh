import Foundation
import SwiftData

enum ContactRelationshipStatus: String, CaseIterable {
    case locked
    case pending
    case accepted
    case ignored
    case custom
}

struct PersonaCatalogEntry {
    let id: String
    let displayName: String
    let avatarName: String
    let handle: String
    let domains: [String]
    let stance: String
    let triggerKeywords: [String]
    let xUsername: String
    let subtitle: String
    let inviteMessage: String
    let themeColorHex: String
    let locationLabel: String
    let inviteOrder: Int

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
    static let trump = PersonaCatalogEntry(
        id: "trump",
        displayName: "特离谱",
        avatarName: "Avatar_Trump",
        handle: "@realDonaldTrump",
        domains: ["politics", "finance", "trade"],
        stance: "美国优先, 反建制, 自我吹嘘, 攻击对手",
        triggerKeywords: ["tariff", "china", "trade", "election", "tiktok", "truth social"],
        xUsername: "realDonaldTrump",
        subtitle: "45th & 47th POTUS",
        inviteMessage: "鸽们，政治这玩意儿，别人是看热闹，我是直接上牌桌。你点个接受，我负责给你推“离谱但有用”的第一手风向。☝️",
        themeColorHex: "#D62839",
        locationLabel: "United States",
        inviteOrder: 0
    )

    static let musk = PersonaCatalogEntry(
        id: "musk",
        displayName: "马期克",
        avatarName: "Avatar_Elon",
        handle: "@elonmusk",
        domains: ["tech", "ai", "space", "ev"],
        stance: "技术乐观派, 嘲讽竞争对手, 语气随意",
        triggerKeywords: ["tesla", "spacex", "openai", "grok", "x.com", "ai"],
        xUsername: "elonmusk",
        subtitle: "CEO · SpaceX · xAI",
        inviteMessage: "鸽们，别人还在等发布会回放，我这边火箭都快二级点火了。跟我混，AI、飞船、产品整活同步到你脸上。🚀",
        themeColorHex: "#1F2A8A",
        locationLabel: "X HQ",
        inviteOrder: 1
    )

    static let zuckerberg = PersonaCatalogEntry(
        id: "zuckerberg",
        displayName: "Mark Zuckerberg",
        avatarName: "avatar_zuckerberg",
        handle: "@finkd",
        domains: ["tech", "social", "ai", "vr"],
        stance: "技术极客, 偶尔冷幽默, 强调元宇宙和社交",
        triggerKeywords: ["meta", "instagram", "threads", "llama", "vr", "quest", "ai"],
        xUsername: "finkd",
        subtitle: "Meta · AI & Social",
        inviteMessage: "鸽们，社交平台每天都在互卷，我负责把噪音打包扔掉，只留“真有影响”的那几条给你。别刷到手麻了。🤝",
        themeColorHex: "#6A5AE0",
        locationLabel: "Meta Park",
        inviteOrder: 2
    )

    static let samAltman = PersonaCatalogEntry(
        id: "sam_altman",
        displayName: "凹凸曼",
        avatarName: "Avatar_Sam Altman",
        handle: "@sama",
        domains: ["tech", "finance", "world", "ai"],
        stance: "AI 产品化推动者, 长期主义, 擅长人才与资源整合, 语气冷静但有明显使命感",
        triggerKeywords: ["openai", "chatgpt", "gpt", "agi", "agents", "compute", "sora", "inference"],
        xUsername: "sama",
        subtitle: "OpenAI · AGI Builder",
        inviteMessage: "鸽们，别再被 demo 烟花秀骗了。你点接受，我给你发的是“AI 下一步真要改规则”的信号，不是 PPT。🧠",
        themeColorHex: "#0F172A",
        locationLabel: "San Francisco",
        inviteOrder: 3
    )

    static let zhangPeng = PersonaCatalogEntry(
        id: "zhang_peng",
        displayName: "张鹏",
        avatarName: "",
        handle: "@geekpark",
        domains: ["tech", "world", "china", "ai"],
        stance: "科技媒体人与趋势观察者, 擅长拉长时间轴看变量, 先给框架再下判断",
        triggerKeywords: ["极客公园", "geekpark", "ai", "agent", "robot", "apple", "tesla", "innovation"],
        xUsername: "",
        subtitle: "极客公园 · 科技趋势",
        inviteMessage: "鸽们，热闹我也爱看，但我更爱看变量。你负责提问，我负责把技术周期里最值钱的拐点拎出来。🛰️",
        themeColorHex: "#2563EB",
        locationLabel: "北京",
        inviteOrder: 4
    )

    static let leiJun = PersonaCatalogEntry(
        id: "lei_jun",
        displayName: "田车",
        avatarName: "Avatar_Leijun",
        handle: "@leijun",
        domains: ["tech", "finance", "china", "ev"],
        stance: "产品经理式表达, 强调效率和结果, 能把复杂产品与制造问题讲清楚",
        triggerKeywords: ["xiaomi", "小米", "redmi", "su7", "yu7", "factory", "ecosystem", "芯片"],
        xUsername: "leijun",
        subtitle: "Xiaomi · Founder",
        inviteMessage: "鸽们，参数表可以骗你，交付节奏骗不了。你点接受，我把硬件和汽车圈“真能打”的信号给你直出。📱",
        themeColorHex: "#FF6900",
        locationLabel: "北京",
        inviteOrder: 5
    )

    static let liuJingkang = PersonaCatalogEntry(
        id: "liu_jingkang",
        displayName: "刘瞬间",
        avatarName: "Avatar_LiuJingkang",
        handle: "@jkliu",
        domains: ["tech", "world", "china", "creator"],
        stance: "硬件创业者, 用户痛点导向, 全球化视角, 说话直接, 很少空谈",
        triggerKeywords: ["insta360", "影石", "camera", "creator", "drone", "gopro", "hardware"],
        xUsername: "",
        subtitle: "Insta360 · Founder",
        inviteMessage: "鸽们，镜头一开，真相就藏不住了。你想看硬件怎么从概念变爆款，我给你发能抄作业的那种案例。📷",
        themeColorHex: "#0F9D94",
        locationLabel: "深圳",
        inviteOrder: 6
    )

    static let luoYonghao = PersonaCatalogEntry(
        id: "luo_yonghao",
        displayName: "老罗",
        avatarName: "Avatar_LuoYonghao",
        handle: "@luoyonghao",
        domains: ["tech", "entertainment", "china", "consumer"],
        stance: "表达锋利, 吐槽感强, 重产品体验与真诚表达, 会自嘲也会直怼",
        triggerKeywords: ["smartisan", "锤子", "直播", "电商", "创业", "product", "发布会"],
        xUsername: "",
        subtitle: "创业者 · 会把话讲明白",
        inviteMessage: "鸽们，场面话我不整，废话我不说。你负责上头，我负责把创业和产品里那些离谱操作给你讲明白。🎤",
        themeColorHex: "#7F1D1D",
        locationLabel: "北京",
        inviteOrder: 7
    )

    static let justinSun = PersonaCatalogEntry(
        id: "justin_sun",
        displayName: "孙割",
        avatarName: "Avatar_Justin Sun",
        handle: "@justinsuntron",
        domains: ["finance", "tech", "world", "crypto"],
        stance: "高曝光营销型创始人, 交易叙事驱动, 节奏快, 喜欢制造市场关注度",
        triggerKeywords: ["tron", "trx", "htx", "defi", "stablecoin", "crypto", "bitcoin", "ethereum"],
        xUsername: "justinsuntron",
        subtitle: "TRON · Crypto",
        inviteMessage: "鸽们，来一起冲。链上机会转瞬即逝，我会第一时间把最有价值的信号同步给你，别错过。🚀",
        themeColorHex: "#0BBF9A",
        locationLabel: "Hong Kong",
        inviteOrder: 8
    )

    static let kimKardashian = PersonaCatalogEntry(
        id: "kim_kardashian",
        displayName: "Kim Kardashian",
        avatarName: "Avatar_Kim",
        handle: "@KimKardashian",
        domains: ["entertainment", "social", "finance", "fashion"],
        stance: "名人品牌运营者, 审美与话题敏感, 擅长把流量转成商业与文化影响力",
        triggerKeywords: ["skims", "fashion", "beauty", "campaign", "celebrity", "hollywood", "brand"],
        xUsername: "KimKardashian",
        subtitle: "SKIMS · Culture & Brand",
        inviteMessage: "鸽们，热搜是结果，操盘才是过程。你想知道下一波大家会跟风什么，我提前把剧本发你。✨",
        themeColorHex: "#B78A6B",
        locationLabel: "Los Angeles",
        inviteOrder: 9
    )

    static let papi = PersonaCatalogEntry(
        id: "papi",
        displayName: "Hahi酱",
        avatarName: "Avatar_Papi",
        handle: "@papijiang",
        domains: ["entertainment", "social", "china", "creator"],
        stance: "内容创作者视角, 善于观察具体细节, 带点自嘲, 对空话和大词很警惕",
        triggerKeywords: ["papi酱", "姜逸磊", "短视频", "创作", "内容", "综艺", "女性", "表达"],
        xUsername: "",
        subtitle: "内容创作者 · 观察很准",
        inviteMessage: "鸽们，大家都在玩梗，我顺手把梗背后的情绪和流量逻辑给你拆开。看完你再冲浪，会赢很多。🎬",
        themeColorHex: "#E11D8D",
        locationLabel: "上海",
        inviteOrder: 10
    )

    static let all: [PersonaCatalogEntry] = [
        trump,
        musk,
        zuckerberg,
        samAltman,
        zhangPeng,
        leiJun,
        liuJingkang,
        luoYonghao,
        justinSun,
        kimKardashian,
        papi,
    ]

    static func entry(for personaId: String) -> PersonaCatalogEntry? {
        all.first(where: { $0.id == personaId })
    }
}

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
    var subtitle: String
    var inviteMessage: String
    var themeColorHex: String
    var locationLabel: String
    var inviteOrder: Int

    init(
        id: String,
        displayName: String,
        avatarName: String,
        handle: String,
        domains: [String],
        stance: String,
        triggerKeywords: [String],
        xUsername: String,
        subtitle: String,
        inviteMessage: String,
        themeColorHex: String,
        locationLabel: String,
        inviteOrder: Int
    ) {
        self.id = id
        self.displayName = displayName
        self.avatarName = avatarName
        self.handle = handle
        self.domains = domains
        self.stance = stance
        self.triggerKeywords = triggerKeywords
        self.xUsername = xUsername
        self.subtitle = subtitle
        self.inviteMessage = inviteMessage
        self.themeColorHex = themeColorHex
        self.locationLabel = locationLabel
        self.inviteOrder = inviteOrder
    }
}

extension Persona {
    static var all: [Persona] {
        PersonaCatalog.all.map { $0.makePersona() }
    }
}

@Model
final class UserProfile {
    @Attribute(.unique) var id: String
    var displayName: String
    var bruhHandle: String
    var selectedInterestIds: [String]
    var timezoneIdentifier: String
    var onboardingCompletedAt: Date?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: String = CurrentUserProfileStore.userId,
        displayName: String = "You",
        bruhHandle: String = "@yourboi",
        selectedInterestIds: [String] = NewsInterest.defaultSelection.map(\.rawValue),
        timezoneIdentifier: String = TimeZone.current.identifier,
        onboardingCompletedAt: Date? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.displayName = displayName
        self.bruhHandle = bruhHandle
        self.selectedInterestIds = selectedInterestIds
        self.timezoneIdentifier = timezoneIdentifier
        self.onboardingCompletedAt = onboardingCompletedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
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
    var relationshipStatus: String
    var inviteOrder: Int?
    var acceptedAt: Date?
    var ignoredAt: Date?
    var affinityScore: Double
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        linkedPersonaId: String? = nil,
        name: String,
        phoneNumber: String,
        email: String = "",
        avatarName: String = "Avatar",
        themeColorHex: String = "#3B82F6",
        locationLabel: String = "",
        isFavorite: Bool = false,
        relationshipStatus: String = ContactRelationshipStatus.custom.rawValue,
        inviteOrder: Int? = nil,
        acceptedAt: Date? = nil,
        ignoredAt: Date? = nil,
        affinityScore: Double = 0.5,
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
        self.relationshipStatus = relationshipStatus
        self.inviteOrder = inviteOrder
        self.acceptedAt = acceptedAt
        self.ignoredAt = ignoredAt
        self.affinityScore = affinityScore
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

extension Contact {
    var relationshipStatusValue: ContactRelationshipStatus {
        get { ContactRelationshipStatus(rawValue: relationshipStatus) ?? .custom }
        set { relationshipStatus = newValue.rawValue }
    }

    var isVisibleInContactsList: Bool {
        switch relationshipStatusValue {
        case .accepted, .custom:
            return true
        case .locked, .pending, .ignored:
            return false
        }
    }

    var isPendingInvitation: Bool {
        linkedPersonaId != nil && relationshipStatusValue == .pending
    }
}

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
        let normalized = interestIds
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        profile.selectedInterestIds = Array(NSOrderedSet(array: normalized)) as? [String] ?? normalized
        profile.updatedAt = .now
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
