import SwiftUI
import TrackCore
import UIKit

// Small shared pieces, as the PWA's ui/parts.tsx. Nothing here animates.

/// A round button holding one icon (the PWA's .control).
struct RoundButton: View {
    let icon: Icon
    let label: String
    /// An icon colour of its own (red for a delete).
    var tint: Color?
    var size = IconSize.regular - 1
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            icon.image(size)
                .foregroundStyle(tint ?? Palette.text)
                .frame(width: Size.control, height: Size.control)
                .raised(.control, .pill)
        }
        .buttonStyle(CardStyle())
        .accessibilityLabel(label)
    }
}

/// A small label pill: green on a green wash ("Up next"), or muted on a faint wash (`plain`).
struct Badge: View {
    let text: String
    var plain = false

    var body: some View {
        Text(text).type(.t12).fontWeight(.bold).monospacedDigit().lineLimit(1)
            .foregroundStyle(plain ? Palette.muted : Palette.accent)
            .padding(.horizontal, Space.s2).padding(.vertical, Space.s1 - 1)
            .background(plain ? Palette.wash : Palette.greenWash, in: Capsule())
    }
}

/// A row of choices, one chosen (the PWA's .seg): a sunk track, the chosen choice raised. The raised knob is the chosen
/// cell's own background, so it is always exactly where its word is, whatever moves. `short` shows each word's first
/// letter (D W M), still read in full; `columns` wraps it onto rows (the picker's muscles).
struct Seg<Value: Hashable>: View {
    let label: String
    let options: [(value: Value, text: String)]
    @Binding var value: Value
    var short = false
    /// Small, inside a row (kg / lb).
    var compact = false
    var columns: Int?

    var body: some View {
        Group {
            if let columns {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Space.s1), count: columns), spacing: Space.s1) { cells }
            } else {
                HStack(spacing: Space.s1) { cells }
            }
        }
        .padding(Space.s1)
        .sunk(columns == nil ? .pill : .wrap)
        .fixedSize(horizontal: short || compact, vertical: false)
        .sensoryFeedback(.selection, trigger: value)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(label)
    }

    private var cells: some View {
        ForEach(options, id: \.value) { option in
            let on = option.value == value
            Button { value = option.value } label: {
                Text(short ? String(option.text.prefix(1)) : option.text)
                    .type(.t14).fontWeight(.semibold).lineLimit(1)
                    .foregroundStyle(on ? Palette.text : Palette.muted)
                    .frame(maxWidth: .infinity, minHeight: compact ? Size.compact : Size.segment)
                    .frame(minWidth: short || compact ? Size.cell : nil)
                    .background { if on { Color.clear.raised(.control, .pill) } }
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(option.text)
            .accessibilityAddTraits(on ? [.isSelected] : [])
        }
    }
}

/// A progress ring with something in its middle; no arc at all at zero.
struct Ring<Inside: View>: View {
    let value: Double
    let size: CGFloat
    let stroke: CGFloat
    let label: String
    @ViewBuilder let inside: Inside

    var body: some View {
        ZStack {
            Circle().inset(by: stroke / 2).stroke(Palette.well, lineWidth: stroke)
            if value > 0 {
                Circle().inset(by: stroke / 2).trim(from: 0, to: min(1, value))
                    .stroke(Palette.accent, style: StrokeStyle(lineWidth: stroke, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            inside
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
    }
}

/// A filled bar for progress toward something (sunk track, raised green fill, or a colour of its own).
struct Bar: View {
    let value: Double
    var color: Color?

    var body: some View {
        Color.clear.frame(height: Size.bar).sunk(.pill)
            .overlay(alignment: .leading) {
                GeometryReader { box in
                    let width = box.size.width * min(1, max(0, value))
                    if width > 0 {
                        if let color { Capsule().fill(color).frame(width: width) } else { Color.clear.frame(width: width).raised(.green, .pill) }
                    }
                }
            }
            .clipShape(Capsule())
    }
}

/// A text field in the sunk well (the PWA's .field), green-ringed while typing in it.
struct Field: View {
    let placeholder: String
    @Binding var text: String
    var label: String?
    /// An icon at its start (the search's magnifier).
    var icon: Icon?
    var keyboard: UIKeyboardType = .default
    var secure = false
    var submit: (() -> Void)?
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: Space.s2) {
            if let icon { icon.image(IconSize.medium).foregroundStyle(Palette.muted).accessibilityHidden(true) }
            if secure { SecureField("", text: $text, prompt: prompt) } else { TextField("", text: $text, prompt: prompt) }
        }
        .type(.t16).fontWeight(.regular)
        .foregroundStyle(Palette.text)
        .keyboardType(keyboard)
        .focused($focused)
        .submitLabel(.done)
        .onSubmit { submit?() }
        .padding(.horizontal, Space.s3 + Space.s1 / 2)
        .frame(height: Size.control)
        .sunk(.inner, ring: focused ? Palette.accent : nil)
        .accessibilityLabel(label ?? placeholder)
    }

    private var prompt: Text { Text(placeholder).foregroundStyle(Palette.placeholder) }
}

/// Rows on one card (the PWA's .card of .row): a hairline between them.
struct RowCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) {
            Group(subviews: content) { rows in
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    row.overlay(alignment: .top) { if index > 0 { Palette.line.frame(height: 1) } }
                }
            }
        }
        .clipShape(Corner.card.shape)
        .raised()
    }
}

/// A row (the PWA's .row): its name, then what sits at its end; 16 all round, a row tall at least.
struct Row<Trailing: View>: View {
    let title: String
    var tint = Palette.text
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: Space.s3) {
            Text(title).type(.t16).foregroundStyle(tint).frame(maxWidth: .infinity, alignment: .leading)
            trailing
        }
        .padding(Space.s4)
        .frame(minHeight: Size.row)
        .contentShape(Rectangle())
    }
}

extension Row where Trailing == RowValue {
    /// A row with a value at its end, and a chevron when it opens something.
    init(title: String, tint: Color = Palette.text, value: String, color: Color = Palette.muted, chevron: Bool = false) {
        self.init(title: title, tint: tint) { RowValue(text: value, color: color, chevron: chevron) }
    }
}

struct RowValue: View {
    let text: String
    var color = Palette.muted
    var chevron = false

    var body: some View {
        HStack(spacing: Space.s2) {
            if !text.isEmpty { Text(text).type(.t14).monospacedDigit().foregroundStyle(color).lineLimit(1) }
            if chevron { Icon.next.image(IconSize.small).foregroundStyle(Palette.muted) }
        }
    }
}

/// A tab's header (the PWA's .head): the title and one control at its end, a control tall.
struct TabHead<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: Space.s3) {
            Text(title).type(.t32).foregroundStyle(Palette.text).accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
            trailing
        }
        .frame(minHeight: Size.control)
    }
}

/// A deeper page's top row (the PWA's TitleBar): back, the title with its line, then any actions.
struct TitleBar<Trailing: View>: View {
    @Environment(AppModel.self) private var model
    let title: String
    var subtitle: String?
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: Space.s3) {
            RoundButton(icon: .back, label: "Back") { model.back() }
            VStack(alignment: .leading, spacing: 0) {
                Text(title).type(.t20).foregroundStyle(Palette.text)
                if let subtitle { Text(subtitle).type(.t14).foregroundStyle(Palette.muted) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
            trailing
        }
        .frame(minHeight: Size.control)
    }
}

extension TitleBar where Trailing == EmptyView {
    init(title: String, subtitle: String? = nil) { self.init(title: title, subtitle: subtitle) { EmptyView() } }
}

/// Two tiles side by side while each has room for its longest line, stacked on narrower phones (the PWA's .tiles).
struct Tiles<A: View, B: View>: View {
    @ViewBuilder let first: A
    @ViewBuilder let second: B

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: Space.s3) {
                first.frame(minWidth: Size.tileMin); second.frame(minWidth: Size.tileMin)
            }
            .fixedSize(horizontal: false, vertical: true)
            VStack(spacing: Space.s3) { first; second }
        }
    }
}

extension View {
    /// A tile's card: 16 all round, its content top left, as tall as its neighbour.
    func tileCard() -> some View { frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).pad().raised() }
}

/// Arranging by drag (the PWA's ArrangeRow and Grip): each row on its card with a grip at its end. The held row follows
/// the finger; the others step aside at once as it crosses them; let go and it moves that many places.
struct ArrangeList<Item: Identifiable, Content: View, End: View>: View {
    let items: [Item]
    let name: (Item) -> String
    let onMove: (_ from: Int, _ to: Int) -> Void
    @ViewBuilder let row: (Item) -> Content
    @ViewBuilder var end: (Item) -> End
    @State private var held: Item.ID?
    @State private var finger = Finger()
    /// Places the held row has crossed: the only part of the drag that redraws the list.
    @State private var steps = 0
    /// One row and the gap under it: a drag's step per place.
    @State private var step = Size.row

    var body: some View {
        let from = items.firstIndex { $0.id == held }
        VStack(spacing: Space.s3) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                HStack(spacing: Space.s3) {
                    row(item).frame(maxWidth: .infinity, alignment: .leading)
                    Icon.grip.image(IconSize.medium).foregroundStyle(Palette.text)
                        .frame(width: Size.control, height: Size.control).raised(.control, .pill)
                        .contentShape(Circle())
                        .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .global)
                            .onChanged {
                                finger.y = $0.translation.height
                                let crossed = max(-index, min(items.count - 1 - index, Int((finger.y / step).rounded())))
                                if held != item.id { held = item.id }
                                if crossed != steps { steps = crossed }
                            }
                            .onEnded { value in
                                // In its new place, it slides in from where the finger left it.
                                finger.y -= CGFloat(steps) * step
                                finger.speed = value.velocity.height
                                if steps != 0 { onMove(index, index + steps) }
                                held = nil
                                steps = 0
                            })
                        .accessibilityLabel("Move \(name(item))")
                    end(item)
                }
                .pad()
                .frame(minHeight: Size.control + Space.s4 * 2)
                .raised()
                .onGeometryChange(for: CGFloat.self) { $0.size.height + Space.s3 } action: { step = $0 }
                .offset(y: room(index, from, steps))
                .follow(finger, while: item.id == held)
                .zIndex(item.id == held ? 1 : 0)
            }
        }
        .sensoryFeedback(.selection, trigger: steps)
    }

    /// Those between the held row's place and where it would go stand one place its way.
    private func room(_ index: Int, _ from: Int?, _ steps: Int) -> CGFloat {
        guard let from, index != from else { return 0 }
        if steps > 0, index > from, index <= from + steps { return -step }
        if steps < 0, index < from, index >= from + steps { return step }
        return 0
    }
}

extension ArrangeList where End == EmptyView {
    init(items: [Item], name: @escaping (Item) -> String, onMove: @escaping (_ from: Int, _ to: Int) -> Void, @ViewBuilder row: @escaping (Item) -> Content) {
        self.init(items: items, name: name, onMove: onMove, row: row, end: { _ in EmptyView() })
    }
}

// MARK: Following a finger

/// Where a finger has dragged something to. Touches only write it; the dragged view reads it once per screen refresh
/// (follow), as iOS's own scroll views do. Redrawn on each touch instead, a touch landing late in a frame missed it,
/// and a slow drag moved every other frame.
final class Finger {
    var y: CGFloat = 0
    /// How fast it was moving when let go (pt/s), so the slide back carries on at that speed.
    var speed: CGFloat = 0
}

extension View {
    /// Moves this view down by the finger's drag, every screen refresh while `on`. Let go, it slides from where the
    /// finger left it (`finger.y`, set to what's left over) back into its place.
    func follow(_ finger: Finger, while on: Bool) -> some View { modifier(Follow(finger: finger, on: on)) }
}

private struct Follow: ViewModifier {
    let finger: Finger
    let on: Bool
    @State private var settle: CGFloat = 0

    func body(content: Content) -> some View {
        TimelineView(.animation(paused: !on)) { _ in content.offset(y: on ? finger.y : settle) }
            .onChange(of: on) { _, now in
                guard !now else { return }
                settle = finger.y
                let speed = finger.speed
                finger.y = 0
                finger.speed = 0
                guard settle != 0 else { return }
                // A spring's starting speed is a share of the distance it covers per second.
                withAnimation(.interpolatingSpring(duration: Motion.fast, bounce: 0, initialVelocity: speed / -settle)) { settle = 0 }
            }
    }
}

// MARK: Sideways swipes

/// A pan that begins only when the finger moves more sideways than up or down, so a row's swipe and the page's scroll
/// never fight.
struct SidewaysPan: UIGestureRecognizerRepresentable {
    /// A release this fast (pt/s) decides by its direction, however short.
    static let flick: CGFloat = 300
    var onChange: (CGFloat) -> Void = { _ in }
    var onEnd: (_ translation: CGFloat, _ velocity: CGFloat) -> Void

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let pan = UIPanGestureRecognizer()
        pan.delegate = context.coordinator
        return pan
    }

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator { Coordinator() }

    func handleUIGestureRecognizerAction(_ pan: UIPanGestureRecognizer, context: Context) {
        let x = pan.translation(in: pan.view).x
        switch pan.state {
        case .changed: onChange(x)
        case .ended, .cancelled, .failed: onEnd(x, pan.velocity(in: pan.view).x)
        default: break
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
            guard let pan = recognizer as? UIPanGestureRecognizer else { return false }
            let velocity = pan.velocity(in: pan.view)
            return abs(velocity.x) > abs(velocity.y)
        }
    }
}

/// The PWA's swipe to arm: the row stays put; a swipe (or flick) left or a long press arms it (its end becomes a red
/// delete), a swipe right disarms it. While armed, a tap on the row disarms instead of opening (the caller checks).
struct SwipeToArm: ViewModifier {
    @Binding var armed: Bool
    /// How long a press arms it.
    static let hold = 0.5

    func body(content: Content) -> some View {
        content
            .contentShape(Rectangle())
            .gesture(SidewaysPan { x, velocity in armed = abs(velocity) > SidewaysPan.flick ? velocity < 0 : x < 0 })
            .onLongPressGesture(minimumDuration: Self.hold) { armed = true }
            .sensoryFeedback(.impact(weight: .heavy), trigger: armed) { _, now in now }
    }
}

extension View {
    func swipeToArm(_ armed: Binding<Bool>) -> some View { modifier(SwipeToArm(armed: armed)) }
}
