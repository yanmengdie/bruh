import Foundation

struct APIClientConfiguration {
    static let current = APIClientConfiguration()

    let appEnvironment: AppEnvironment
    let functionsBaseURL: String
    let anonKey: String

    init(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        bundle: Bundle = .main,
        appEnvironment: AppEnvironment? = nil,
        functionsBaseURL: String? = nil,
        anonKey: String? = nil
    ) {
        let resolvedEnvironment = appEnvironment ?? AppEnvironment.resolve(environment: environment, bundle: bundle)
        self.appEnvironment = resolvedEnvironment
        self.functionsBaseURL = Self.resolveString(
            override: functionsBaseURL,
            environmentKeys: ["BRUH_FUNCTIONS_BASE_URL", "SUPABASE_FUNCTIONS_BASE_URL"],
            bundleKeys: ["BRUH_FUNCTIONS_BASE_URL", "SUPABASE_FUNCTIONS_BASE_URL"],
            appEnvironment: resolvedEnvironment,
            environment: environment,
            bundle: bundle,
            defaultValue: "https://mrxctelezutprdeemqla.supabase.co/functions/v1"
        ).trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        self.anonKey = Self.resolveString(
            override: anonKey,
            environmentKeys: ["BRUH_SUPABASE_ANON_KEY", "SUPABASE_ANON_KEY"],
            bundleKeys: ["BRUH_SUPABASE_ANON_KEY", "SUPABASE_ANON_KEY"],
            appEnvironment: resolvedEnvironment,
            environment: environment,
            bundle: bundle,
            defaultValue: "sb_publishable_ry_i_qMeMDzxeE7qhSl1UA_XcAwgQL1"
        )
    }

    private static func resolveString(
        override: String?,
        environmentKeys: [String],
        bundleKeys: [String],
        appEnvironment: AppEnvironment,
        environment: [String: String],
        bundle: Bundle,
        defaultValue: String
    ) -> String {
        if let override, !override.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return override.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        for key in appEnvironment.scopedKeys(for: environmentKeys) {
            if let value = environment[key]?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty {
                return value
            }
        }

        for key in appEnvironment.scopedKeys(for: bundleKeys) {
            if let value = bundle.object(forInfoDictionaryKey: key) as? String {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    return trimmed
                }
            }
        }

        return defaultValue
    }
}
