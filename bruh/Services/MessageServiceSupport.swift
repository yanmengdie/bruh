import Foundation

enum MessageServiceSupport {
    static let trumpWebPreviewDemoMessageId = "seed-trump-reuters-og"

    static func starterMessageText(for personaId: String) -> String {
        PersonaCatalog.starterMessage(for: personaId)
    }

    static func starterMessageId(for personaId: String) -> String {
        "starter:\(personaId)"
    }

    static func hasPlayableAudio(_ message: PersonaMessage) -> Bool {
        guard let audioUrl = message.audioUrl?.trimmingCharacters(in: .whitespacesAndNewlines) else {
            return false
        }
        return !audioUrl.isEmpty
    }

    static func messagePreview(
        text: String,
        imageUrl: String?,
        audioUrl: String? = nil,
        audioOnly: Bool = false
    ) -> String {
        if audioOnly, let audioUrl, !audioUrl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "[语音]"
        }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard imageUrl != nil else { return trimmed }
        return trimmed.isEmpty ? "[图片]" : "[图片] \(trimmed)"
    }
}
