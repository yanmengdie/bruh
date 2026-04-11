import Foundation

struct AppRuntimeOptions {
    static let current = AppRuntimeOptions()

    private let environment: [String: String]
    private let defaults: UserDefaults
    private let bundle: Bundle
    private let appEnvironment: AppEnvironment

    init(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        defaults: UserDefaults = .standard,
        bundle: Bundle = .main,
        appEnvironment: AppEnvironment? = nil
    ) {
        self.environment = environment
        self.defaults = defaults
        self.bundle = bundle
        self.appEnvironment = appEnvironment ?? AppEnvironment.resolve(environment: environment, bundle: bundle)
    }

    var shouldBootstrapBundledMoments: Bool {
        resolveFlag(
            envKey: "BRUH_SEED_BUNDLED_MOMENTS",
            userDefaultsKey: "runtime.seedBundledMoments",
            defaultValue: defaultDemoFlagValue
        )
    }

    var shouldApplyDemoInviteOrder: Bool {
        resolveFlag(
            envKey: "BRUH_ENABLE_DEMO_INVITE_ORDER",
            userDefaultsKey: "runtime.enableDemoInviteOrder",
            defaultValue: defaultDemoFlagValue
        )
    }

    var shouldSeedFallbackStarters: Bool {
        resolveFlag(
            envKey: "BRUH_ENABLE_LOCAL_STARTER_FALLBACKS",
            userDefaultsKey: "runtime.enableLocalStarterFallbacks",
            defaultValue: defaultDemoFlagValue
        )
    }

    var shouldInjectMessageDemoArtifacts: Bool {
        resolveFlag(
            envKey: "BRUH_ENABLE_MESSAGE_DEMO_ARTIFACTS",
            userDefaultsKey: "runtime.enableMessageDemoArtifacts",
            defaultValue: defaultDemoFlagValue
        )
    }

    var shouldUseLocalFeedInteractionFallbacks: Bool {
        resolveFlag(
            envKey: "BRUH_ENABLE_LOCAL_FEED_INTERACTION_FALLBACKS",
            userDefaultsKey: "runtime.enableLocalFeedInteractionFallbacks",
            defaultValue: defaultDemoFlagValue
        )
    }

    private var defaultDemoFlagValue: Bool {
#if DEBUG
        appEnvironment == .dev
#else
        false
#endif
    }

    private func resolveFlag(
        envKey: String,
        userDefaultsKey: String,
        defaultValue: Bool
    ) -> Bool {
        for key in appEnvironment.scopedKeys(for: [envKey]) {
            if let rawValue = environment[key], let parsed = Self.parseBool(rawValue) {
                return parsed
            }
        }

        for key in appEnvironment.scopedKeys(for: [envKey]) {
            if let rawValue = bundle.object(forInfoDictionaryKey: key) {
                switch rawValue {
                case let boolValue as Bool:
                    return boolValue
                case let stringValue as String:
                    if let parsed = Self.parseBool(stringValue) {
                        return parsed
                    }
                default:
                    break
                }
            }
        }

        for key in [appEnvironment.scopedUserDefaultsKey(userDefaultsKey), userDefaultsKey] {
            if let rawValue = defaults.object(forKey: key) {
                switch rawValue {
                case let boolValue as Bool:
                    return boolValue
                case let stringValue as String:
                    if let parsed = Self.parseBool(stringValue) {
                        return parsed
                    }
                default:
                    break
                }
            }
        }

        return defaultValue
    }

    private static func parseBool(_ rawValue: String) -> Bool? {
        switch rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "1", "true", "yes", "on":
            return true
        case "0", "false", "no", "off":
            return false
        default:
            return nil
        }
    }
}
