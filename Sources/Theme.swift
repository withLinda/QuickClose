import SwiftUI

enum Theme {
    static let panelHex: UInt32 = 0x1E2326
    static let fieldHex: UInt32 = 0x272E33
    static let primaryTextHex: UInt32 = 0xD3C6AA
    static let secondaryTextHex: UInt32 = 0x9DA9A0
    static let accentHex: UInt32 = 0xE69875
    static let panel = color(panelHex)
    static let field = color(fieldHex)
    static let border = color(0x7A8478).opacity(0.45)
    static let primaryText = color(primaryTextHex)
    static let secondaryText = color(secondaryTextHex)
    static let accent = color(accentHex)
    static let onAccent = panel

    private static func color(_ hex: UInt32) -> Color {
        Color(.sRGB, red: Double((hex >> 16) & 255) / 255, green: Double((hex >> 8) & 255) / 255, blue: Double(hex & 255) / 255)
    }
}
