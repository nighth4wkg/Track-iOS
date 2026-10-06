import SwiftUI

/// Track's colours that the rest Live Activity draws too: the widget extension can't see the app's Palette, so both
/// read them here.
enum Hex {
    /// The dark theme's mint (Palette.primary and accent).
    static let mint: UInt32 = 0x48E58D
    /// The dark theme's page (Palette.background).
    static let night: UInt32 = 0x121418
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255, opacity: opacity)
    }
}
