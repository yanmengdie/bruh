import Foundation
import SwiftData

enum ContentGraphStoreSupport {
    @MainActor
    static func fetchSourceItem(id: String, in context: ModelContext) -> SourceItem? {
        var descriptor = FetchDescriptor<SourceItem>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    @MainActor
    static func fetchContentEvent(id: String, in context: ModelContext) -> ContentEvent? {
        var descriptor = FetchDescriptor<ContentEvent>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    @MainActor
    static func fetchContentDelivery(id: String, in context: ModelContext) -> ContentDelivery? {
        var descriptor = FetchDescriptor<ContentDelivery>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    static func resolvedEventKind(for message: PersonaMessage) -> ContentEventKind {
        if normalizedValue(message.imageUrl) != nil {
            return .generatedImage
        }
        if message.isSeedMessage || !message.sourcePostIds.isEmpty {
            return .messageStarter
        }
        return .messageReply
    }

    static func previewText(
        text: String,
        imageUrl: String? = nil,
        audioUrl: String? = nil,
        audioOnly: Bool = false
    ) -> String {
        if audioOnly, normalizedValue(audioUrl) != nil {
            return "[Voice]"
        }

        let trimmed = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)

        let base = trimmed.isEmpty ? (imageUrl == nil ? "Untitled" : "[图片]") : String(trimmed.prefix(80))
        return base
    }

    static func firstURL(in text: String) -> String? {
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return detector?
            .matches(in: text, options: [], range: range)
            .compactMap { $0.url?.absoluteString }
            .first
    }

    static func normalizedValue(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    static func deduplicated(_ values: [String]) -> [String] {
        Array(NSOrderedSet(array: values)) as? [String] ?? values
    }
}
