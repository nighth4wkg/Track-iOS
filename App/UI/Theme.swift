import SwiftUI
import TrackCore
import UIKit

// Track's look, token for token the PWA's (Track-pwa pwa/src/styles.css :root): dark only, solid surfaces lit from
// above, built from two recipes. RAISED (cards, sheets, controls, tiles, buttons, the nav pill): a top-to-bottom shade,
// a faint light line along the top edge and a small soft shadow. SUNK (fields, segment tracks, bars): a darker well
// with a soft inner shadow at the top. Nothing animates: every change shows at once.
enum Palette {
    static let background = Color(hex: Hex.night)
    static let text = Color(hex: 0xF7F8F6)
    static let muted = Color(hex: 0xA9B0B6)
    static let placeholder = Color(hex: 0x7D858C)
    static let faint = Color(hex: 0x5A6066)
    static let accent = Color(hex: Hex.mint)
    /// Behind a green label (a badge), and a picked day.
    static let greenWash = Color(hex: Hex.mint, opacity: 0.12)
    static let greenPick = Color(hex: Hex.mint, opacity: 0.15)
    /// Words on the green button.
    static let onGreen = Color(hex: 0x0B2A18)
    static let danger = Color(hex: 0xFF6B6B)
    /// The SUNK well.
    static let well = Color(hex: 0x0E1013)
    static let handle = Color(hex: 0x6E757C)
    /// Last period's bars on the Progress chart.
    static let previous = Color(hex: 0x30343B)
    static let line = Color.white.opacity(0.12)
    static let wash = Color.white.opacity(0.06)
    static let scrim = Color.black.opacity(0.65)
    /// Starter, Novice, Solid, Strong, Elite (the PWA's --rank-0 to --rank-4).
    static let ranks: [Color] = [Color(hex: 0xA9B0B6), Color(hex: 0x5AA7EC), Color(hex: 0x4CC38A), Color(hex: 0xE8A93A), Color(hex: 0xB287F5)]
}

/// The RAISED fills, top to bottom.
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

/// 16 page edge, card padding, title to content; 8 label to content; 12 between cards; 24 between sections; 4 tight.
enum Space {
    static let s1: CGFloat = 4, s2: CGFloat = 8, s3: CGFloat = 12, s4: CGFloat = 16, s6: CGFloat = 24
}

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
    static let navWidth: CGFloat = 344
    /// A small segment button, and a segment button.
    static let compact: CGFloat = 32
    static let segment: CGFloat = 36
    static let emblem: CGFloat = 56
    /// A progress bar, a chart bar, a trained day's dot, the sheet's handle.
    static let bar: CGFloat = 8
    static let chartBar: CGFloat = 10
    static let dot: CGFloat = 5
    static let handle = CGSize(width: 40, height: 5)
    static let chart: CGFloat = 96
    /// The narrowest a side-by-side tile gets.
    static let tileMin: CGFloat = 160
    /// The page column and the sign-in column.
    static let column: CGFloat = 600
    static let narrow: CGFloat = 480
}

/// Rings: across, and stroke (the PWA's RINGS).
enum Rings {
    static let level = (size: CGFloat(96), stroke: CGFloat(8))
    static let week = (size: CGFloat(88), stroke: CGFloat(8))
    static let rest = (size: CGFloat(36), stroke: CGFloat(4))
}

enum IconSize {
    static let small: CGFloat = 16, medium: CGFloat = 18, regular: CGFloat = 20, logo: CGFloat = 22, emblem: CGFloat = 26
}

enum Radius {
    static let small: CGFloat = 4, inner: CGFloat = 12, card: CGFloat = 18, sheet: CGFloat = 28
    /// A segment that wraps onto rows (the picker's muscles) rounds like this, not as a pill.
    static let wrap: CGFloat = 22
}

enum Corner {
    case small, inner, card, sheet, wrap, pill

    /// iOS's own rounded box: drawn without working out a path on the CPU.
    var shape: RoundedRectangle {
        switch self {
        case .small: RoundedRectangle(cornerRadius: Radius.small, style: .continuous)
        case .inner: RoundedRectangle(cornerRadius: Radius.inner, style: .continuous)
        case .card: RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
        case .sheet: RoundedRectangle(cornerRadius: Radius.sheet, style: .continuous)
        case .wrap: RoundedRectangle(cornerRadius: Radius.wrap, style: .continuous)
        // Fully round ends; a circle when square.
        case .pill: RoundedRectangle(cornerRadius: .greatestFiniteMagnitude, style: .circular)
        }
    }
}

/// The PWA's t-12 to t-32: size, line height and weight, growing with the system text size.
enum TextStyle {
    case t12, t14, t16, t20, t28, t32

    var size: CGFloat {
        switch self { case .t12: 12; case .t14: 15; case .t16: 17; case .t20: 20; case .t28: 28; case .t32: 32 }
    }
    var lineHeight: CGFloat {
        switch self { case .t12: 16; case .t14: 20; case .t16: 22; case .t20: 28; case .t28: 34; case .t32: 40 }
    }
    var weight: Font.Weight {
        switch self { case .t12, .t16: .semibold; case .t14: .regular; case .t20, .t28, .t32: .bold }
    }
    /// t-32 sits a little tighter (-0.01em).
    var tracking: CGFloat { self == .t32 ? -size / 100 : 0 }
    var relative: Font.TextStyle {
        switch self { case .t12: .caption; case .t14: .subheadline; case .t16: .headline; case .t20: .title3; case .t28: .title; case .t32: .largeTitle }
    }
}

/// A text style at the system text size: the font, and the PWA's line height made up around the font's own (half
/// above, half below, and between lines).
private struct Typeset: ViewModifier {
    @ScaledMetric var size: CGFloat
    @ScaledMetric var line: CGFloat
    let weight: Font.Weight
    let tracking: CGFloat

    init(_ style: TextStyle) {
        _size = ScaledMetric(wrappedValue: style.size, relativeTo: style.relative)
        _line = ScaledMetric(wrappedValue: style.lineHeight, relativeTo: style.relative)
        weight = style.weight
        tracking = style.tracking
    }

    func body(content: Content) -> some View {
        let natural = UIFont.systemFont(ofSize: size, weight: UIFont.Weight(weight)).lineHeight
        let extra = max(0, line - natural)
        content.font(.system(size: size, weight: weight)).tracking(tracking)
            .lineSpacing(extra).padding(.vertical, extra / 2)
    }
}

private extension UIFont.Weight {
    init(_ weight: Font.Weight) {
        switch weight {
        case .semibold: self = .semibold
        case .bold: self = .bold
        default: self = .regular
        }
    }
}

extension View {
    func type(_ style: TextStyle) -> some View { modifier(Typeset(style)) }
}

/// The page backdrop: one flat colour.
struct Backdrop: View {
    var body: some View { Palette.background.ignoresSafeArea() }
}

/// RAISED: the shade, a light line along the top edge, a small soft shadow drawn from the shape alone.
struct Raised: ViewModifier {
    let surface: Surface
    let corner: Corner

    func body(content: Content) -> some View {
        let shape = corner.shape
        let shade = LinearGradient(colors: surface.shade, startPoint: .top, endPoint: .bottom)
        let fade = LinearGradient(stops: [.init(color: .white.opacity(surface.edge), location: 0),
                                          .init(color: .white.opacity(0.04), location: 0.12)], startPoint: .top, endPoint: .bottom)
        // The edge line as three plain fills (shade, the fading white over it, the shade again 1 pt in): no mask or
        // stroke, so no offscreen pass per card.
        content.background {
            shape.fill(shade)
                .shadow(color: .black.opacity(0.45), radius: 4, y: 3)
                .overlay(shape.fill(fade))
                .overlay(shape.inset(by: 1).fill(shade))
        }
    }
}

/// SUNK: the dark well with a soft inner shadow at its top; a ring (green focused, red wrong) when given.
struct Sunk: ViewModifier {
    let corner: Corner
    var ring: Color?

    func body(content: Content) -> some View {
        let shape = corner.shape
        content.background {
            shape.fill(Palette.well.shadow(.inner(color: .black.opacity(0.65), radius: 1.5, y: 1)))
                .overlay(shape.strokeBorder(ring ?? .white.opacity(0.03), lineWidth: ring == nil ? 1 : 2))
        }
    }
}

extension View {
    func raised(_ surface: Surface = .card, _ corner: Corner = .card) -> some View { modifier(Raised(surface: surface, corner: corner)) }
    func sunk(_ corner: Corner = .inner, ring: Color? = nil) -> some View { modifier(Sunk(corner: corner, ring: ring)) }
    /// A card's insides: 16 all round.
    func pad() -> some View { padding(Space.s4) }
}

/// How a pressed button answers, at once (no motion yet): a little darker. Disabled ones don't answer.
private struct Pressed: ViewModifier {
    let on: Bool
    func body(content: Content) -> some View { content.opacity(on ? 0.75 : 1) }
}

/// The screen's main action: the green pill. `compact` beside other controls: a control's height, as wide as its words.
struct PrimaryStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    var compact = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .type(.t16).fontWeight(.bold)
            .foregroundStyle(enabled ? Palette.onGreen : Palette.muted)
            .padding(.horizontal, compact ? Space.s4 : Space.s6)
            .frame(maxWidth: compact ? nil : .infinity, minHeight: compact ? Size.control : Size.primary)
            .modifier(Fill(enabled: enabled))
            .modifier(Pressed(on: configuration.isPressed && enabled))
    }

    /// Disabled, it stays solid in a control's shade (see-through, the list showed through it).
    private struct Fill: ViewModifier {
        let enabled: Bool
        func body(content: Content) -> some View {
            if enabled { content.raised(.green, .pill) } else { content.raised(.control, .pill) }
        }
    }
}

/// Every other button: a raised control pill; `danger` says it deletes, in red.
struct SecondaryStyle: ButtonStyle {
    var danger = false
    var height = Size.control
    /// As wide as its words (a sheet's Done), not the row.
    var hug = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .type(.t16)
            .foregroundStyle(danger ? Palette.danger : Palette.text)
            .padding(.horizontal, hug ? Space.s4 + Space.s1 / 2 : 0)
            .frame(maxWidth: hug ? nil : .infinity, minHeight: height)
            .raised(.control, .pill)
            .modifier(Pressed(on: configuration.isPressed))
    }
}

/// A row inside a card: it lights up while pressed, as iOS lists do (it doesn't dim or shrink inside its card).
struct RowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.background(configuration.isPressed ? Palette.wash : .clear)
    }
}

/// A whole card that opens something.
struct CardStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { configuration.label.modifier(Pressed(on: configuration.isPressed)) }
}

/// The Track mark: the hex dumbbell turned 45 degrees (ui/icons.tsx Mark), never green.
struct TrackMark: View {
    var size: CGFloat = IconSize.logo

    var body: some View {
        Canvas { context, canvas in
            let unit = canvas.width / 24
            context.translateBy(x: canvas.width / 2, y: canvas.height / 2)
            context.rotate(by: .degrees(-45))
            context.translateBy(x: -canvas.width / 2, y: -canvas.height / 2)
            let r = { (x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat) in CGRect(x: x * unit, y: y * unit, width: w * unit, height: h * unit) }
            // The two hex plates, each with a slot down its middle.
            for (left, slot) in [(CGFloat(0.8), CGFloat(4.65)), (16.2, 18.45)] {
                var plate = Path()
                let w: CGFloat = 7
                plate.move(to: CGPoint(x: left * unit, y: 8.2 * unit))
                plate.addLine(to: CGPoint(x: (left + 2.4) * unit, y: 5.8 * unit))
                plate.addLine(to: CGPoint(x: (left + 4.6) * unit, y: 5.8 * unit))
                plate.addLine(to: CGPoint(x: w * unit + left * unit, y: 8.2 * unit))
                plate.addLine(to: CGPoint(x: w * unit + left * unit, y: 15.8 * unit))
                plate.addLine(to: CGPoint(x: (left + 4.6) * unit, y: 18.2 * unit))
                plate.addLine(to: CGPoint(x: (left + 2.4) * unit, y: 18.2 * unit))
                plate.addLine(to: CGPoint(x: left * unit, y: 15.8 * unit))
                plate.closeSubpath()
                plate.addRect(r(slot, 7.4, 0.9, 9.2))
                context.fill(plate, with: .foreground, style: FillStyle(eoFill: true))
            }
            for x in [CGFloat(7.2), 15.4] { context.fill(Path(roundedRect: r(x, 9.4, 1.4, 5.2), cornerRadius: 0.5 * unit), with: .foreground) }
            var handle = Path(r(8.2, 10.3, 7.6, 3.4))
            handle.addRect(r(10.35, 10.9, 1, 2.2))
            handle.addRect(r(12.65, 10.9, 1, 2.2))
            context.fill(handle, with: .foreground, style: FillStyle(eoFill: true))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// Every icon, by the PWA's names: SF Symbols at its sizes.
enum Icon: String {
    case home = "house", history = "calendar", progress = "chart.bar", rank = "medal", back = "chevron.left",
         next = "chevron.right", down = "chevron.down", up = "chevron.up", arrange = "arrow.up.arrow.down",
         grip = "line.3.horizontal", plus = "plus", check = "checkmark", close = "xmark", alert = "exclamationmark.circle",
         play = "play.fill", search = "magnifyingglass", filter = "line.3.horizontal.decrease", more = "ellipsis",
         trash = "trash", settings = "gearshape", eye = "eye"

    func image(_ size: CGFloat = IconSize.regular, bold: Bool = false) -> some View {
        Image(systemName: rawValue).font(.system(size: size, weight: bold ? .bold : .semibold))
    }
}

extension View {
    /// A floating part (nav pill, rest timer, toast, docked button) Space.s4 above the SCREEN's bottom edge, over the
    /// home indicator's strip as iOS's own floating bars sit (owner: not lifted above it as on Android). For a view laid
    /// out inside the bottom safe area.
    func floatingBottom(_ above: CGFloat = 0) -> some View { padding(.bottom, Space.s4 + above - homeIndicator) }
}

/// The home indicator's strip (0 on a phone with a home button), never the keyboard.
@MainActor var homeIndicator: CGFloat {
    UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow }.first?.safeAreaInsets.bottom ?? 0
}

// MARK: Words and numbers, as the PWA's fmt.ts

/// A total weight in the chosen unit, whole, grouped: "10,805".
func weight(_ kg: Double, _ unit: TrackCore.Settings.Unit) -> String {
    (kg * (unit == .lb ? Limits.poundsPerKilogram : 1)).formatted(.number.precision(.fractionLength(0)))
}

/// "1 exercise", "3 sets".
func count(_ value: Int, _ noun: String) -> String { "\(value) \(noun)\(value == 1 ? "" : "s")" }

/// " · " between facts on one line.
let dot = " · "

/// "0:42" or "1:05:09" since a start, at `now`.
func elapsed(_ start: Int, _ now: Date) -> String {
    let seconds = max(0, Int(now.timeIntervalSince1970) - start / 1000)
    return seconds >= 3600 ? String(format: "%d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60)
        : String(format: "%d:%02d", seconds / 60, seconds % 60)
}

/// "1:30".
func clock(_ seconds: Int) -> String { String(format: "%d:%02d", seconds / 60, seconds % 60) }

/// "today", "yesterday", "3 days ago": calendar days, so last night is yesterday this morning.
func ago(_ time: Int, now: Int = nowMillis()) -> String {
    let day = { (t: Int) in Calendars.local.startOfDay(for: Date(timeIntervalSince1970: Double(t) / 1000)) }
    let days = Calendars.local.dateComponents([.day], from: day(time), to: day(now)).day ?? 0
    return days < 1 ? "today" : days == 1 ? "yesterday" : "\(days) days ago"
}

extension FormatStyle where Self == Date.FormatStyle {
    /// Dates as the PWA writes them, in English and the Gregorian calendar whatever the phone's region ("Sep 23").
    static var gregorian: Date.FormatStyle { Date.FormatStyle(locale: Locale(identifier: "en"), calendar: Calendars.local, timeZone: .current) }
}
