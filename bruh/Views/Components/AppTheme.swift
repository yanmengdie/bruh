import SwiftUI

enum AppTheme {
    // Shared warm background used by Messages list/detail surfaces.
    static let messagesBackground = Color(red: 0.93, green: 0.91, blue: 0.87)
    static let messageBubbleBase = Color(red: 0.95, green: 0.95, blue: 0.95)
    static let outgoingBubbleBase = Color(red: 0.90, green: 0.88, blue: 0.82)

    static func color(from hex: String, fallback: Color = .blue) -> Color {
        let cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "#", with: "")
        guard cleaned.count == 6, let value = Int(cleaned, radix: 16) else {
            return fallback
        }

        let r = Double((value >> 16) & 0xFF) / 255.0
        let g = Double((value >> 8) & 0xFF) / 255.0
        let b = Double(value & 0xFF) / 255.0
        return Color(red: r, green: g, blue: b)
    }
}
