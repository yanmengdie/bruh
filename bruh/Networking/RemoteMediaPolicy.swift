import Foundation

enum RemoteMediaPolicy {
    private static let trustedAssetHTTPUpgradeHostSuffixes = [
        "video.weibocdn.com"
    ]

    static func normalizedSourceURLString(_ rawValue: String?) -> String? {
        normalizedURLString(rawValue, allowHTTP: true)
    }

    static func normalizedAssetURLString(_ rawValue: String?) -> String? {
        normalizedURLString(rawValue, allowHTTP: false)
    }

    static func normalizedSourceURL(_ rawValue: String?) -> URL? {
        guard let normalized = normalizedSourceURLString(rawValue) else { return nil }
        return URL(string: normalized)
    }

    static func normalizedAssetURL(_ rawValue: String?) -> URL? {
        guard let normalized = normalizedAssetURLString(rawValue) else { return nil }
        return URL(string: normalized)
    }

    static func normalizedMediaURLStrings(_ rawValues: [String], limit: Int = 9) -> [String] {
        var results: [String] = []
        var seen = Set<String>()

        for rawValue in rawValues {
            guard let normalized = normalizedAssetURLString(rawValue) else { continue }
            guard seen.insert(normalized).inserted else { continue }
            results.append(normalized)
            if results.count >= limit {
                break
            }
        }

        return results
    }

    static func normalizedMediaURLs(_ rawValues: [String], limit: Int = 9) -> [URL] {
        normalizedMediaURLStrings(rawValues, limit: limit).compactMap(URL.init(string:))
    }

    private static func normalizedURLString(_ rawValue: String?, allowHTTP: Bool) -> String? {
        guard let trimmed = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }

        guard var components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(),
              let host = components.host?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !host.isEmpty else {
            return nil
        }

        switch scheme {
        case "https":
            break
        case "http" where allowHTTP:
            break
        case "http" where shouldUpgradeAssetHTTPHost(host):
            components.scheme = "https"
            if components.port == 80 {
                components.port = nil
            }
        default:
            return nil
        }

        guard components.user == nil, components.password == nil else {
            return nil
        }

        guard !isLoopbackOrPrivateHost(host) else {
            return nil
        }

        components.fragment = nil
        return components.url?.absoluteString
    }

    private static func isLoopbackOrPrivateHost(_ host: String) -> Bool {
        let normalized = host.trimmingCharacters(in: CharacterSet(charactersIn: "[]")).lowercased()
        if normalized.isEmpty {
            return true
        }

        if normalized == "localhost" ||
            normalized == "::1" ||
            normalized == "0.0.0.0" ||
            normalized.hasSuffix(".local") ||
            normalized.hasSuffix(".internal") {
            return true
        }

        let octets = normalized.split(separator: ".")
        guard octets.count == 4 else {
            return false
        }

        let parsed = octets.compactMap { Int($0) }
        guard parsed.count == 4, parsed.allSatisfy({ (0...255).contains($0) }) else {
            return true
        }

        return parsed[0] == 0 ||
            parsed[0] == 10 ||
            parsed[0] == 127 ||
            (parsed[0] == 169 && parsed[1] == 254) ||
            (parsed[0] == 172 && (16...31).contains(parsed[1])) ||
            (parsed[0] == 192 && parsed[1] == 168)
    }

    private static func shouldUpgradeAssetHTTPHost(_ host: String) -> Bool {
        let normalized = host.trimmingCharacters(in: CharacterSet(charactersIn: "[]")).lowercased()
        guard !normalized.isEmpty else { return false }

        return trustedAssetHTTPUpgradeHostSuffixes.contains { suffix in
            normalized == suffix || normalized.hasSuffix(".\(suffix)")
        }
    }
}
