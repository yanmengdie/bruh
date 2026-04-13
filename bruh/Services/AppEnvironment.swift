import Foundation

enum AppEnvironment: String, CaseIterable {
    case dev
    case staging
    case prod

    static let current = resolve()

    static func resolve(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        bundle: Bundle = .main
    ) -> AppEnvironment {
        if let rawValue = resolveString(
            environmentKeys: ["BRUH_APP_ENV", "BRUH_ENV"],
            bundleKeys: ["BRUH_APP_ENV", "BRUH_ENV"],
            environment: environment,
            bundle: bundle
        ), let normalized = AppEnvironment(normalizing: rawValue) {
            return normalized
        }

#if DEBUG
        return .dev
#else
        return .prod
#endif
    }

    init?(normalizing rawValue: String) {
        switch rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "dev", "development", "local", "debug":
            self = .dev
        case "staging", "stage", "stg", "qa", "test":
            self = .staging
        case "prod", "production", "release", "live":
            self = .prod
        default:
            return nil
        }
    }

    var configSuffix: String {
        rawValue.uppercased()
    }

    func scopedKeys(for baseKeys: [String]) -> [String] {
        var keys: [String] = []
        var seen = Set<String>()

        for key in baseKeys {
            let scopedKey = "\(key)__\(configSuffix)"
            if seen.insert(scopedKey).inserted {
                keys.append(scopedKey)
            }
        }

        for key in baseKeys {
            if seen.insert(key).inserted {
                keys.append(key)
            }
        }

        return keys
    }

    func scopedUserDefaultsKey(_ baseKey: String) -> String {
        if let suffixIndex = baseKey.firstIndex(of: ".") {
            let prefix = baseKey[..<suffixIndex]
            let suffix = baseKey[baseKey.index(after: suffixIndex)...]
            return "\(prefix).\(rawValue).\(suffix)"
        }
        return "\(rawValue).\(baseKey)"
    }

    private static func resolveString(
        environmentKeys: [String],
        bundleKeys: [String],
        environment: [String: String],
        bundle: Bundle
    ) -> String? {
        for key in environmentKeys {
            if let value = environment[key]?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty {
                return value
            }
        }

        for key in bundleKeys {
            if let value = bundle.object(forInfoDictionaryKey: key) as? String {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    return trimmed
                }
            }
        }

        return nil
    }
}

struct ScopedUserDefaultsStore {
    let userDefaults: UserDefaults
    let appEnvironment: AppEnvironment

    init(
        userDefaults: UserDefaults = .standard,
        appEnvironment: AppEnvironment = .current
    ) {
        self.userDefaults = userDefaults
        self.appEnvironment = appEnvironment
    }

    @discardableResult
    func key(_ baseKey: String) -> String {
        let scopedKey = appEnvironment.scopedUserDefaultsKey(baseKey)
        migrateLegacyValueIfNeeded(for: baseKey, scopedKey: scopedKey)
        return scopedKey
    }

    func string(for baseKey: String) -> String? {
        userDefaults.string(forKey: key(baseKey))
    }

    func data(for baseKey: String) -> Data? {
        userDefaults.data(forKey: key(baseKey))
    }

    func bool(for baseKey: String) -> Bool {
        userDefaults.bool(forKey: key(baseKey))
    }

    func set(_ value: Any?, for baseKey: String) {
        let scopedKey = key(baseKey)
        if let value {
            userDefaults.set(value, forKey: scopedKey)
        } else {
            userDefaults.removeObject(forKey: scopedKey)
        }
    }

    func removeObject(for baseKey: String) {
        userDefaults.removeObject(forKey: appEnvironment.scopedUserDefaultsKey(baseKey))
    }

    private func migrateLegacyValueIfNeeded(for baseKey: String, scopedKey: String) {
        guard userDefaults.object(forKey: scopedKey) == nil else { return }
        guard let legacyValue = userDefaults.object(forKey: baseKey) else { return }
        userDefaults.set(legacyValue, forKey: scopedKey)
    }
}
