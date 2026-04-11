import Foundation

private let pengyouMomentFractionalDateFormatter: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter
}()

private let pengyouMomentDateFormatter: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return formatter
}()

func pengyouDate(_ value: String) -> Date {
    if let date = pengyouMomentFractionalDateFormatter.date(from: value) {
        return date
    }

    return pengyouMomentDateFormatter.date(from: value) ?? .now
}

enum PengyouMomentSeedSupport {
    static func normalizedValue(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    static func normalizedMediaURLs(_ values: [String]) -> [String] {
        values.compactMap(normalizedValue)
    }
}
