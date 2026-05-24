import Foundation
import SwiftUI

struct WebPreviewCardData {
    let source: String
    let heroText: String
    let headline: String
    let summary: String
    let imageURL: URL?
    let link: URL

    static func fallback(for url: URL) -> WebPreviewCardData {
        let host = url.host?.replacingOccurrences(of: "www.", with: "") ?? "LINK"
        let source = host.components(separatedBy: ".").first?.uppercased() ?? "LINK"

        return WebPreviewCardData(
            source: source,
            heroText: source,
            headline: url.absoluteString,
            summary: "Link preview",
            imageURL: nil,
            link: url
        )
    }
}

@MainActor
final class OpenGraphPreviewStore: ObservableObject {
    @Published private var cache: [String: WebPreviewCardData] = [:]
    private var inFlight: Set<String> = []

    func preview(for url: URL) -> WebPreviewCardData {
        cache[url.absoluteString] ?? .fallback(for: url)
    }

    func load(url: URL) async {
        let key = url.absoluteString
        if cache[key] != nil || inFlight.contains(key) { return }
        inFlight.insert(key)
        defer { inFlight.remove(key) }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                return
            }

            guard let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
                return
            }

            if let parsed = OpenGraphParser.parse(html: html, pageURL: url) {
                cache[key] = parsed
            }
        } catch {
            return
        }
    }
}

enum OpenGraphParser {
    static func parse(html: String, pageURL: URL) -> WebPreviewCardData? {
        let title = firstMetaContent(html: html, keys: ["og:title", "twitter:title"]) ?? pageTitle(html: html)
        let description = firstMetaContent(html: html, keys: ["og:description", "twitter:description", "description"])
        let imageString = firstMetaContent(html: html, keys: ["og:image", "twitter:image"])
        let siteName = firstMetaContent(html: html, keys: ["og:site_name"]) ?? domainLabel(from: pageURL)

        guard title != nil || description != nil || imageString != nil else { return nil }

        let imageURL = resolveURL(imageString, relativeTo: pageURL)
        let headline = decoded(title ?? pageURL.absoluteString)
        let summary = decoded(description ?? "Open link for details")
        let source = decoded(siteName.uppercased())

        return WebPreviewCardData(
            source: source,
            heroText: heroText(from: source),
            headline: headline,
            summary: summary,
            imageURL: imageURL,
            link: pageURL
        )
    }

    static func firstMetaContent(html: String, keys: [String]) -> String? {
        for key in keys {
            if let value = firstMetaContent(html: html, key: key), !value.isEmpty {
                return value
            }
        }
        return nil
    }

    static func firstMetaContent(html: String, key: String) -> String? {
        let patterns = [
            "<meta[^>]*?(?:property|name)\\s*=\\s*[\"']\(NSRegularExpression.escapedPattern(for: key))[\"'][^>]*?content\\s*=\\s*[\"']([^\"']+)[\"'][^>]*?>",
            "<meta[^>]*?content\\s*=\\s*[\"']([^\"']+)[\"'][^>]*?(?:property|name)\\s*=\\s*[\"']\(NSRegularExpression.escapedPattern(for: key))[\"'][^>]*?>"
        ]

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
                continue
            }
            let range = NSRange(html.startIndex..<html.endIndex, in: html)
            if let match = regex.firstMatch(in: html, options: [], range: range),
               match.numberOfRanges > 1,
               let capture = Range(match.range(at: 1), in: html) {
                return String(html[capture]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        return nil
    }

    static func pageTitle(html: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: "<title[^>]*>(.*?)</title>", options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return nil
        }
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        guard let match = regex.firstMatch(in: html, options: [], range: range),
              match.numberOfRanges > 1,
              let capture = Range(match.range(at: 1), in: html) else {
            return nil
        }

        return String(html[capture]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func resolveURL(_ raw: String?, relativeTo baseURL: URL) -> URL? {
        guard let raw, !raw.isEmpty else { return nil }
        if let absolute = URL(string: raw), absolute.scheme != nil {
            return absolute
        }
        return URL(string: raw, relativeTo: baseURL)?.absoluteURL
    }

    static func domainLabel(from url: URL) -> String {
        let host = url.host?.replacingOccurrences(of: "www.", with: "") ?? "LINK"
        return host.components(separatedBy: ".").first?.uppercased() ?? "LINK"
    }

    static func heroText(from source: String) -> String {
        let cleaned = source.replacingOccurrences(of: " ", with: "")
        return String(cleaned.prefix(10))
    }

    static func decoded(_ value: String) -> String {
        var decoded = value
        let entities: [String: String] = [
            "&amp;": "&",
            "&quot;": "\"",
            "&#39;": "'",
            "&lt;": "<",
            "&gt;": ">"
        ]
        for (entity, replacement) in entities {
            decoded = decoded.replacingOccurrences(of: entity, with: replacement)
        }
        return decoded
    }
}
