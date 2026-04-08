import Foundation

enum NewsInterest: String, CaseIterable, Identifiable {
    case politics
    case entertainment
    case sports
    case finance
    case tech
    case world
    case china

    var id: String { rawValue }

    static let defaultSelection: [NewsInterest] = [.politics, .sports, .tech]

    var title: String {
        switch self {
        case .politics: return "政治"
        case .entertainment: return "娱乐"
        case .sports: return "体育"
        case .finance: return "金融"
        case .tech: return "科技"
        case .world: return "国际"
        case .china: return "中国"
        }
    }

    var subtitle: String {
        switch self {
        case .politics: return "选举、政策、地缘政治"
        case .entertainment: return "明星、影视、综艺、流行文化"
        case .sports: return "比赛、转会、热点人物"
        case .finance: return "市场、贸易、宏观经济"
        case .tech: return "AI、平台、产品、芯片"
        case .world: return "国际热点与全球大事"
        case .china: return "和中国相关的重点事件"
        }
    }
}

enum InterestPreferences {
    private static let defaults = UserDefaults.standard
    private static let keyPrefix = "news_interest_"

    static func isEnabled(_ interest: NewsInterest, userDefaults: UserDefaults = defaults) -> Bool {
        userDefaults.bool(forKey: keyPrefix + interest.rawValue)
    }

    static func set(_ enabled: Bool, for interest: NewsInterest, userDefaults: UserDefaults = defaults) {
        userDefaults.set(enabled, forKey: keyPrefix + interest.rawValue)
    }

    static func legacySelectedInterests(userDefaults: UserDefaults = defaults) -> [String] {
        NewsInterest.allCases
            .filter { isEnabled($0, userDefaults: userDefaults) }
            .map(\.rawValue)
    }
}
