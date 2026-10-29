import SwiftUI

enum Theme {
    static let canvasTop = Color(red: 0.90, green: 0.93, blue: 0.95)
    static let canvasBottom = Color(red: 0.84, green: 0.88, blue: 0.91)
    static let card = Color(red: 0.99, green: 0.99, blue: 1.0)
    static let cardStroke = Color(red: 0.78, green: 0.82, blue: 0.86)
    static let ink = Color(red: 0.10, green: 0.13, blue: 0.16)
    static let muted = Color(red: 0.35, green: 0.40, blue: 0.45)
    static let accent = Color(red: 0.12, green: 0.48, blue: 0.40)
    static let accentBlue = Color(red: 0.15, green: 0.40, blue: 0.65)
    static let warn = Color(red: 0.62, green: 0.28, blue: 0.10)
    static let danger = Color(red: 0.66, green: 0.22, blue: 0.18)
    static let sidebar = Color(red: 0.94, green: 0.95, blue: 0.96)

    static func cardBackground() -> some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(card)
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(cardStroke, lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.06), radius: 8, y: 2)
    }
}
