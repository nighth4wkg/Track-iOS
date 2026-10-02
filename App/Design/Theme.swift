import SwiftUI

// Track's Sheen theme, from the website's tokens (app/styles/sheen-theme.css, liquid-glass.css, appearance.css):
// glass surfaces with a light rim, one mint accent used sparingly, and the system font at Dynamic Type sizes.
enum Palette {
    static let background = Color(light: 0xEEF1F6, dark: 0x121418)
    static let text = Color(light: 0x232731, dark: 0xF7F8F6)
    static let muted = Color(light: 0x59616E, dark: 0xC0C7C5)
    static let hairline = Color(light: 0xC8CDD6, dark: 0x6C7779).opacity(0.55)
    /// The one accent: text and small marks. Big green blocks are only the primary button.
    static let accent = Color(light: 0x0A7A48, dark: 0x48E58D)
    static let primary = Color(light: 0x3FD583, dark: 0x48E58D)
    static let primaryText = Color(light: 0x0D2A1A, dark: 0x102B1C)
    static let danger = Color(hex: 0xE52626)
    /// The streak flame (components/header-streak).
    static let streak = Color(light: 0xC2620E, dark: 0xF5A546)
    static let card = Color(light: 0xFFFFFF, dark: 0xFFFFFF, lightOpacity: 0.58, darkOpacity: 0.05)
    static let control = Color(light: 0xFFFFFF, dark: 0xFFFFFF, lightOpacity: 0.70, darkOpacity: 0.08)
    static let input = Color(light: 0xE7EBF2, dark: 0x000000, lightOpacity: 0.78, darkOpacity: 0.22)
    static let rim = Color(light: 0xFFFFFF, dark: 0xFFFFFF, lightOpacity: 1, darkOpacity: 0.24)
    static let shadow = Color(light: 0x2A3A52, dark: 0x000000, lightOpacity: 0.08, darkOpacity: 0.35)
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255, opacity: opacity)
    }

    /// A colour that follows light and dark mode.
    init(light: UInt32, dark: UInt32, lightOpacity: Double = 1, darkOpacity: Double = 1) {
        self.init(UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(Color(hex: dark, opacity: darkOpacity))
                : UIColor(Color(hex: light, opacity: lightOpacity))
        })
    }
}

/// The page backdrop: the theme colour with the website's soft glows.
struct Backdrop: View {
    var body: some View {
        ZStack {
            Palette.background
            RadialGradient(colors: [Color(hex: 0x2F6F8F, opacity: 0.16), .clear], center: .topLeading, startRadius: 0, endRadius: 520)
            RadialGradient(colors: [Palette.primary.opacity(0.08), .clear], center: .trailing, startRadius: 0, endRadius: 420)
        }
        .ignoresSafeArea()
    }
}

/// A glass surface: a translucent fill, the sheen across its top-left, and a light rim (the website's --glass-face
/// and --glass-edge).
struct Glass: ViewModifier {
    var radius: CGFloat = 20
    var fill: Color = Palette.card
    var lifted = true

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content
            .background {
                shape.fill(fill)
                    .overlay(shape.fill(LinearGradient(colors: [.white.opacity(0.09), .white.opacity(0.02), .clear],
                                                       startPoint: .topLeading, endPoint: UnitPoint(x: 0.6, y: 0.6))))
                    .overlay(shape.strokeBorder(LinearGradient(colors: [Palette.rim, Palette.rim.opacity(0.2)],
                                                               startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1))
                    .shadow(color: lifted ? Palette.shadow : .clear, radius: 15, y: 10)
            }
    }
}

extension View {
    func glass(radius: CGFloat = 20, fill: Color = Palette.card, lifted: Bool = true) -> some View {
        modifier(Glass(radius: radius, fill: fill, lifted: lifted))
    }
}

/// The screen's one main action: the green pill.
struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(Palette.primaryText)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(Capsule().fill(Palette.primary)
                .overlay(Capsule().fill(LinearGradient(colors: [.white.opacity(0.18), .clear], startPoint: .topLeading, endPoint: UnitPoint(x: 0.55, y: 0.55))))
                .shadow(color: Palette.shadow, radius: 6, y: 4))
            .opacity(configuration.isPressed ? 0.8 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

/// Every other button: a glass pill.
struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(Palette.text)
            .frame(maxWidth: .infinity, minHeight: 50)
            .glass(radius: 25, fill: Palette.control, lifted: false)
            .opacity(configuration.isPressed ? 0.7 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

/// The Track mark: a barbell of five rounded bars (components/track-mark.tsx), never green.
struct TrackMark: View {
    var size: CGFloat = 22

    var body: some View {
        Canvas { context, canvas in
            let unit = canvas.width / 24
            for (x, y, w, h) in [(1.0, 5.5, 3.0, 13.0), (5, 7.5, 3, 9), (8, 11, 8, 2), (16, 7.5, 3, 9), (20, 5.5, 3, 13)] {
                let rect = CGRect(x: x * unit, y: y * unit, width: w * unit, height: h * unit)
                context.fill(Path(roundedRect: rect, cornerRadius: unit), with: .foreground)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// The brand as in the website's top bar.
struct Brand: View {
    var body: some View {
        HStack(spacing: 8) {
            TrackMark()
            Text("track").font(.title3.weight(.semibold)).tracking(-0.8)
        }
        .foregroundStyle(Palette.text)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Track")
    }
}
