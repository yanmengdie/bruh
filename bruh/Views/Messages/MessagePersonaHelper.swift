import SwiftUI

enum MessagePersonaHelper {
    static func fallbackTint(for personaId: String) -> Color {
        switch personaId {
        case "trump":
            return .orange
        case "musk":
            return .blue
        case "sam_altman":
            return Color(red: 0.06, green: 0.12, blue: 0.22)
        case "zhang_peng":
            return Color(red: 0.15, green: 0.39, blue: 0.92)
        case "lei_jun":
            return Color(red: 1.00, green: 0.41, blue: 0.00)
        case "luo_yonghao":
            return Color(red: 0.50, green: 0.11, blue: 0.11)
        case "justin_sun":
            return Color(red: 0.11, green: 0.74, blue: 0.63)
        case "kim_kardashian":
            return Color(red: 0.72, green: 0.54, blue: 0.42)
        case "papi":
            return Color(red: 0.88, green: 0.11, blue: 0.55)
        case "cristiano_ronaldo":
            return Color(red: 0.05, green: 0.58, blue: 0.53)
        default:
            return .gray
        }
    }

    static func persona(for personaId: String, contacts: [Contact]) -> (name: String, tint: Color) {
        if let contact = contacts.first(where: { $0.linkedPersonaId == personaId }) {
            return (contact.name, AppTheme.color(from: contact.themeColorHex, fallback: fallbackTint(for: personaId)))
        }
        return (personaId.capitalized, fallbackTint(for: personaId))
    }
}
