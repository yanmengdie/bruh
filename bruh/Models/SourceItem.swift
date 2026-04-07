import Foundation
import SwiftData

@Model
final class SourceItem {
    @Attribute(.unique) var id: String
    var sourceType: String       // "x" | "news_rss" | "news_api"
    var sourceName: String
    var title: String
    var content: String
    var url: String
    var tags: [String]
    var publishedAt: Date
    var fetchedAt: Date
    var isVerified: Bool
    var isProcessed: Bool

    init(
        id: String = UUID().uuidString,
        sourceType: String,
        sourceName: String,
        title: String,
        content: String,
        url: String,
        tags: [String] = [],
        publishedAt: Date = .now,
        fetchedAt: Date = .now,
        isVerified: Bool = false,
        isProcessed: Bool = false
    ) {
        self.id = id
        self.sourceType = sourceType
        self.sourceName = sourceName
        self.title = title
        self.content = content
        self.url = url
        self.tags = tags
        self.publishedAt = publishedAt
        self.fetchedAt = fetchedAt
        self.isVerified = isVerified
        self.isProcessed = isProcessed
    }
}
