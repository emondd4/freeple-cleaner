import SwiftUI

enum Theme {
    /// Soft teal-slate canvas — practical, high contrast, not purple/cream AI defaults.
    static let canvasTop = Color(red: 0.93, green: 0.96, blue: 0.97)
    static let canvasBottom = Color(red: 0.86, green: 0.91, blue: 0.94)
    static let card = Color(red: 1.0, green: 1.0, blue: 1.0)
    static let cardStroke = Color(red: 0.72, green: 0.80, blue: 0.84)
    static let ink = Color(red: 0.08, green: 0.14, blue: 0.18)
    static let muted = Color(red: 0.32, green: 0.40, blue: 0.46)
    static let accent = Color(red: 0.05, green: 0.55, blue: 0.52)
    static let accentBlue = Color(red: 0.12, green: 0.42, blue: 0.72)
    static let accentWarm = Color(red: 0.92, green: 0.45, blue: 0.18)
    static let warn = Color(red: 0.72, green: 0.42, blue: 0.08)
    static let danger = Color(red: 0.78, green: 0.22, blue: 0.28)
    static let sidebar = Color(red: 0.95, green: 0.97, blue: 0.98)
    static let sidebarSelected = Color(red: 0.05, green: 0.55, blue: 0.52)
    static let chip = Color(red: 0.90, green: 0.96, blue: 0.95)

    static func cardBackground(radius: CGFloat = 16) -> some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(card)
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(cardStroke.opacity(0.85), lineWidth: 1)
            )
            .shadow(color: Color(red: 0.05, green: 0.20, blue: 0.25).opacity(0.08), radius: 10, y: 3)
    }

    static func heroChip(color: Color = accent) -> some View {
        Capsule()
            .fill(color.opacity(0.14))
    }
}
