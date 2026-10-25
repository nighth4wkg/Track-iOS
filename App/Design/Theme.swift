import SwiftUI
import TrackCore

// Track's look, the same as the PWA's (Track-pwa pwa/src/styles.css :root): dark only, solid surfaces lit from above,
// built from two recipes. RAISED (cards, sheets, controls, tiles, buttons, the nav pill): a gentle top-to-bottom shade,
// a faint light line along the top edge, a hairline and a small soft shadow. SUNK (fields, segment tracks, bars): a
// darker well with a soft inner shadow at the top. No blur and no large shadows: the cheapest paint there is.
// Every colour, space, size and radius is a token here; views use only these names.
enum Palette {
    static let background = Color(hex: Hex.night)
    static let text = Color(hex: 0xF7F8F6)
    static let muted = Color(hex: 0xA9B0B6)
    static let placeholder = Color(hex: 0x7D858C)
    static let faint = Color(hex: 0x5A6066)
    /// The one accent, for text, marks and the main button.
    static let accent = Color(hex: Hex.mint)
    static let primary = accent
    /// A soft green behind a green label (the Up next badge), and a picked day.
    static let greenWash = Color(hex: Hex.mint, opacity: 0.12)
    static let greenPick = Color(hex: Hex.mint, opacity: 0.15)
    static let primaryText = Color(hex: 0x0B2A18)
    static let danger = Color(hex: 0xFF6B6B)
    static let dangerText = danger
    /// The SUNK well: fields, segment tracks, empty bars.
    static let input = Color(hex: 0x0E1013)
    static let handle = Color(hex: 0x6E757C)
    /// Last period's bars on the Progress chart.
    static let previous = Color(hex: 0x30343B)
    static let hairline = Color.white.opacity(0.12)
    static let wash = Color.white.opacity(0.06)
    static let dim = Color.black.opacity(0.65)
    static let action = Color(hex: 0x4F5762)
}

/// The RAISED surfaces' fills, top to bottom, by what they are.
enum Surface {
    case card, sheet, nav, float, control, green

    var shade: [Color] {
        switch self {
        case .card: [Color(hex: 0x22252B), Color(hex: 0x1C1F24)]
        case .sheet: [Color(hex: 0x25292F), Color(hex: 0x1E2126)]
        case .nav: [Color(hex: 0x24272D), Color(hex: 0x1D2025)]
        case .float: [Color(hex: 0x292D33), Color(hex: 0x22252B)]
        case .control: [Color(hex: 0x30343B), Color(hex: 0x272B31)]
        case .green: [Color(hex: 0x5AEE9A), Color(hex: 0x44DC87)]
        }
    }
    /// The light line along the top edge: brighter on green.
    var edge: Double { self == .green ? 0.4 : 0.08 }
}

/// Space, as the PWA: 16 page edge, card padding and title-to-content; 8 label-to-content; 12 between cards in a
/// group; 24 between sections; 4 inside tight groups.
enum Space {
    static let s1: CGFloat = 4, s2: CGFloat = 8, s3: CGFloat = 12, s4: CGFloat = 16, s6: CGFloat = 24
}

/// Sizes, as the PWA.
enum Size {
    /// Every tap target: round buttons, fields, done keys, set rows.
    static let control: CGFloat = 44
    /// The main action.
    static let primary: CGFloat = 48
    /// Numbered tiles, calendar days.
    static let tile: CGFloat = 40
    /// One set-table column.
    static let cell: CGFloat = 48
    /// A list row.
    static let row: CGFloat = 56
    /// The floating nav pill and rest timer.
    static let nav: CGFloat = 60
    /// The widest the nav pill gets.
    static let navWidth: CGFloat = 344
    /// A small segment button.
    static let compact: CGFloat = 32
    /// A segment button (Progress's measures).
    static let segment: CGFloat = 36
    /// One bar of a chart.
    static let chartBar: CGFloat = 10
    /// The Rank emblem and the sign-in mark.
    static let emblem: CGFloat = 56
    /// A progress bar.
    static let bar: CGFloat = 8
    /// A trained day's mark on the calendar.
    static let dot: CGFloat = 5
    /// The Progress chart.
    static let chart: CGFloat = 96
    /// Home's week ring, and its stroke.
    static let weekRing: CGFloat = 88
    static let ringStroke: CGFloat = 8
    /// The level ring on Workout complete.
    static let levelRing: CGFloat = 96
    /// The rest timer's ring and its line.
    static let restRing: CGFloat = 36
    static let restStroke: CGFloat = 4
    /// The narrowest a side-by-side tile gets.
    static let tileMin: CGFloat = 160
}

/// Icon sizes, as the PWA's ICON.
enum IconSize {
    static let small: CGFloat = 16, medium: CGFloat = 18, regular: CGFloat = 20, logo: CGFloat = 22, emblem: CGFloat = 26
}

/// Corners, as the PWA.
enum Radius {
    static let small: CGFloat = 4, inner: CGFloat = 12, card: CGFloat = 18, sheet: CGFloat = 28
}

/// The shape a surface takes: a rounded box at one of the radii, a pill, or a circle.
enum Corner {
    case small, inner, card, sheet, pill, circle

    var shape: Rounded {
        switch self {
        case .small: Rounded(radius: Radius.small)
        case .inner: Rounded(radius: Radius.inner)
        case .card: Rounded(radius: Radius.card)
        case .sheet: Rounded(radius: Radius.sheet)
        case .pill, .circle: Rounded(radius: nil)
        }
    }

    /// shortcut: -nativeShape test switch (60 Hz pass): iOS's own rounded box, which it draws without a custom path.
    var native: RoundedRectangle {
        let radius = shape.radius
        return RoundedRectangle(cornerRadius: radius ?? .greatestFiniteMagnitude, style: radius == nil ? .circular : .continuous)
    }
}

/// A box with continuous corners at a radius, or fully round ends (a pill, or a circle when square) when it has none.
struct Rounded: InsettableShape {
    let radius: CGFloat?
    var inset: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let box = rect.insetBy(dx: inset, dy: inset)
        guard let radius else { return RoundedRectangle(cornerRadius: min(box.width, box.height) / 2, style: .circular).path(in: box) }
        return RoundedRectangle(cornerRadius: max(0, radius - inset), style: .continuous).path(in: box)
    }

    func inset(by amount: CGFloat) -> Rounded { Rounded(radius: radius, inset: inset + amount) }
}

/// Text styles, as the PWA's t-12 to t-32 (the iPhone's caption, subheadline, headline, title3, title and large
/// title sizes), growing with the system text size.
enum TextStyle {
    case t12, t14, t16, t20, t28, t32

    var size: CGFloat {
        switch self { case .t12: 12; case .t14: 15; case .t16: 17; case .t20: 20; case .t28: 28; case .t32: 32 }
    }
    var weight: Font.Weight {
        switch self { case .t12, .t16: .semibold; case .t14: .regular; case .t20, .t28, .t32: .bold }
    }
    /// The large title sits a little tighter, as the PWA's t-32 (-0.01em).
    var tracking: CGFloat { self == .t32 ? -size / 100 : 0 }
    var relative: Font.TextStyle {
        switch self { case .t12: .caption; case .t14: .subheadline; case .t16: .headline; case .t20: .title3; case .t28: .title; case .t32: .largeTitle }
    }
}

/// Track's motion timings in seconds (the PWA's --motion-fast and --motion).
enum Motion {
    static let fast = 0.16, standard = 0.24
    static let quick = 0.2, slow = 0.35
    /// A sheet sliding away: what opening another one from it waits for.
    static let sheetAway = 0.45
    /// The workout sliding up over the tabs, or away (as iOS's own full-screen pages).
    static let screen = 0.45
    /// How small a pressed button gets.
    static let press = 0.97
    /// A long press that arms a row's delete, as the PWA's list gesture.
    static let hold = 0.5
}

/// The widest a page's column gets, and a card's corners.
enum Measure {
    static let page: CGFloat = 600
    /// The sign-in column, as the PWA's --narrow.
    static let narrow: CGFloat = 480
    static let card: CGFloat = Radius.card
}

/// One of the PWA's fixed sizes that still grows with the system text size (Dynamic Type).
private struct ScaledFont: ViewModifier {
    @ScaledMetric var size: CGFloat
    let weight: Font.Weight

    init(size: CGFloat, weight: Font.Weight, relativeTo style: Font.TextStyle = .body) {
        _size = ScaledMetric(wrappedValue: size, relativeTo: style)
        self.weight = weight
    }

    func body(content: Content) -> some View { content.font(.system(size: size, weight: weight)) }
}

extension View {
    func scaledFont(_ size: CGFloat, weight: Font.Weight = .regular) -> some View {
        modifier(ScaledFont(size: size, weight: weight))
    }
    /// One of the PWA's text styles.
    func type(_ style: TextStyle) -> some View {
        modifier(ScaledFont(size: style.size, weight: style.weight, relativeTo: style.relative)).tracking(style.tracking)
    }
}

/// The page backdrop: one flat colour, as the PWA.
struct Backdrop: View {
    var body: some View { Palette.background.ignoresSafeArea() }
}

/// RAISED: the surface's shade, a light line along its top edge over a hairline, and a small soft shadow. The shadow
/// is drawn from the shape (not the content), so it needs no offscreen pass.
struct Raised: ViewModifier {
    let surface: Surface
    let corner: Corner

    func body(content: Content) -> some View {
        if Probe.has("-nativeShape") { paint(content, corner.native) } else { paint(content, corner.shape) }
    }

    private func paint(_ content: Content, _ shape: some InsettableShape) -> some View {
        let edge = shape.strokeBorder(LinearGradient(stops: [.init(color: .white.opacity(surface.edge), location: 0),
                                                             .init(color: .white.opacity(0.04), location: 0.12)],
                                                     startPoint: .top, endPoint: .bottom), lineWidth: 1)
        return content.background {
            // The shadow on the bare shape, before the edge goes on: cast by the fill and its edge together, it was
            // worked out offscreen on every frame a card moved.
            shape.fill(LinearGradient(colors: surface.shade, startPoint: .top, endPoint: .bottom))
                .shadow(color: Probe.has("-noShadow") ? .clear : .black.opacity(0.45), radius: 4, y: 3)
                .overlay(edge)
        }
    }
}

/// SUNK: the dark well with a soft inner shadow at its top; a ring (green while focused, red when wrong) when given.
struct Sunk: ViewModifier {
    let corner: Corner
    var ring: Color?

    func body(content: Content) -> some View {
        if Probe.has("-nativeShape") { paint(content, corner.native) } else { paint(content, corner.shape) }
    }

    private func paint(_ content: Content, _ shape: some InsettableShape) -> some View {
        content.background {
            shape.fill(Probe.has("-noInner") ? AnyShapeStyle(Palette.input) : AnyShapeStyle(Palette.input.shadow(.inner(color: .black.opacity(0.65), radius: 1.5, y: 1))))
                .overlay(shape.strokeBorder(ring ?? .white.opacity(0.03), lineWidth: ring == nil ? 1 : 2))
        }
    }
}

extension View {
    func raised(_ surface: Surface = .card, _ corner: Corner = .card) -> some View { modifier(Raised(surface: surface, corner: corner)) }
    func sunk(_ corner: Corner = .inner, ring: Color? = nil) -> some View { modifier(Sunk(corner: corner, ring: ring)) }
}

/// The screen's one main action: the green pill (RAISED green), shrinking a little while pressed.
struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    /// In a bar beside other controls (Finish, Skip): a control's height and as wide as its label.
    var compact = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .type(.t16).fontWeight(.bold)
            .foregroundStyle(Palette.primaryText)
            .padding(.horizontal, compact ? Space.s4 : 0)
            .frame(maxWidth: compact ? nil : .infinity, minHeight: compact ? Size.control : Size.primary)
            .raised(.green, .pill)
            .scaleEffect(configuration.isPressed ? Motion.press : 1)
            .opacity(enabled ? 1 : 0.45)
            .animation(.smooth(duration: Motion.fast), value: configuration.isPressed)
    }
}

/// Every other button: a RAISED control pill; one that deletes says so in red (the PWA's discard).
struct SecondaryButtonStyle: ButtonStyle {
    var danger = false
    /// Beside or in place of the main button, it takes the main button's height.
    var height = Size.control
    /// As wide as its label (a sheet's Done), not the row.
    var hug = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .type(.t16)
            .foregroundStyle(danger ? Palette.danger : Palette.text)
            .padding(.horizontal, hug ? Space.s4 : 0)
            .frame(maxWidth: hug ? nil : .infinity, minHeight: height)
            .raised(.control, .pill)
            .scaleEffect(configuration.isPressed ? Motion.press : 1)
            .animation(.smooth(duration: Motion.fast), value: configuration.isPressed)
    }
}

/// The Track mark: a barbell of five rounded bars (components/track-mark.tsx), never green.
struct TrackMark: View {
    var size: CGFloat = IconSize.logo

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

/// The brand at the top of Home, as the PWA's: the mark beside "track".
struct Brand: View {
    var body: some View {
        HStack(spacing: Space.s2) {
            TrackMark(size: IconSize.logo)
            Text("track").type(.t20)
        }
        .foregroundStyle(Palette.text)
        .accessibilityElement(children: .ignore) // read once, as "Track" (the lowercase word inside was read too)
        .accessibilityLabel("Track")
    }
}

extension View {
    /// A floating bar (the nav pill, the rest timer) Space.s4 above the screen's bottom edge, over the home indicator's
    /// strip as the PWA's --clear, when laid out inside the safe area. Measured from the window: an overlay's
    /// ignoresSafeArea left the pill a whole strip higher on the iPhone.
    func floatingBottom() -> some View { padding(.bottom, Space.s4 - homeIndicator) }
}

/// The home indicator's strip at the bottom of the screen (0 on a phone with a home button), never the keyboard.
@MainActor var homeIndicator: CGFloat {
    UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow }.first?.safeAreaInsets.bottom ?? 0
}
