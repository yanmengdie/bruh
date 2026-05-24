import Foundation
import SwiftUI
import SwiftData

struct MessageReaction {
    let emoji: String
    let mood: String

    static let presets: [MessageReaction] = [
        .init(emoji: "😌", mood: "chill"),
        .init(emoji: "🔥", mood: "excited"),
        .init(emoji: "😎", mood: "confident"),
        .init(emoji: "🤔", mood: "curious"),
        .init(emoji: "🙂", mood: "calm"),
        .init(emoji: "🥳", mood: "hyped")
    ]
}

protocol MessageTimestampProviding {
    func timestampLabel(for message: PersonaMessage, previous: PersonaMessage?) -> String?
}

struct RealTimeMessageTimestampProvider: MessageTimestampProviding {
    func timestampLabel(for message: PersonaMessage, previous: PersonaMessage?) -> String? {
        let gap: TimeInterval = 5 * 60
        if let previous, message.createdAt.timeIntervalSince(previous.createdAt) < gap {
            return nil
        }

        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.doesRelativeDateFormatting = true
        formatter.timeStyle = .short
        formatter.dateStyle = Calendar.current.isDateInToday(message.createdAt) ? .none : .medium
        return formatter.string(from: message.createdAt)
    }
}
