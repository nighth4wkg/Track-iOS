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
    var size = IconSize.round
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
            .padding(.horizontal, Space.s2).padding(.vertical, Pad.badge)
            .background(plain ? Palette.wash : Palette.greenWash, in: Capsule())
    }
}

/// A row of choices, one chosen (the PWA's .seg): a sunk track, the chosen choice under the raised knob (KnobRow).
/// `short` shows each word's first letter (D W M), still read in full; `columns` wraps it onto rows (the picker's
/// muscles). A choice that should move the page as a tap does (a list it filters) passes `moves`.
struct Seg<Value: Hashable>: View {
    let label: String
    let options: [(value: Value, text: String)]
    @Binding var value: Value
    var short = false
    /// Small, inside a row (kg / lb).
    var compact = false
    var columns: Int?
    var moves = false

    var body: some View {
        KnobRow(values: options.map(\.value), chosen: value, columns: columns,
                choose: { next in if moves { Motion.tap { value = next } } else { value = next } }) { choice, lit in
            let text = options.first { $0.value == choice }?.text ?? ""
            Text(short ? String(text.prefix(1)) : text)
                .type(.t14).fontWeight(.semibold).lineLimit(1)
                .foregroundStyle(lit ? Palette.text : Palette.muted)
                .frame(maxWidth: .infinity, minHeight: compact ? Size.compact : Size.segment)
                .frame(minWidth: short || compact ? Size.cell : nil)
                .accessibilityLabel(text)
        }
        .padding(Space.s1)
        .sunk(columns == nil ? .pill : .wrap)
        .fixedSize(horizontal: short || compact, vertical: false)
        .sensoryFeedback(.selection, trigger: value)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(label)
    }
}

/// Choices drawn as the nav pill is, in the page (the PWA's Tabs: Settings' sections): an icon over each name, the
/// chosen one green under the knob. Its own sections show at once; only the knob moves.
struct PillTabs<Value: Hashable>: View {
    let label: String
    let items: [(value: Value, text: String, icon: (Bool) -> AnyView)]
    let chosen: Value
    /// The nav pill's width; on a page (Settings) as wide as its cards.
    var width = Size.navWidth
    let choose: (Value) -> Void

    var body: some View {
        KnobRow(values: items.map(\.value), chosen: chosen, choose: choose) { value, lit in
            let item = items.first { $0.value == value }
            VStack(spacing: Gap.tab) {
                item?.icon(lit)
                Text(item?.text ?? "").type(.t12)
            }
            .foregroundStyle(lit ? Palette.accent : Palette.muted)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(item?.text ?? "")
        }
        .padding(Space.s1)
        .frame(maxWidth: width)
        .frame(height: Size.nav)
        .raised(.nav, .pill)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(label)
    }
}

/// The raised knob under a row's chosen choice, shared by every Seg, PillTabs and the nav pill (the PWA's knob: owner,
/// every bar works the same). It slides to a new choice; it comes to a pressed one at once (not waiting on the lift);
/// dragged sideways it follows the finger freely in a row (a grid's goes to the nearest), the choice nearest it lit (a
/// tick each), and letting go chooses that one, the knob settling on it (build 70's shared row only hopped; the nav
/// pill's had followed the finger before, owner). Only the
/// knob moves: what the choice changes elsewhere shows as its caller decides (`choose`).
struct KnobRow<Value: Hashable, Cell: View>: View {
    let values: [Value]
    let chosen: Value
    var columns: Int?
    let choose: (Value) -> Void
    @ViewBuilder let cell: (_ value: Value, _ lit: Bool) -> Cell
    @Namespace private var space
    /// The choice under the finger: pressed, or nearest while dragging. Kept until the choice lands, so the knob never
    /// shows the old one for a frame between the lift and the change.
    @State private var held: Value?
    @State private var dragging = false
    /// The finger's x while a row's knob follows it; nil sits the knob on its choice.
    @State private var finger: CGFloat?
    @State private var ticks = 0
    /// Each choice's frame, for a drag to find the nearest. Not observed: measuring them mustn't redraw the row.
    @State private var spots = Spots()
    private final class Spots { var frames: [Value: CGRect] = [:] }
    private static var area: String { "knob row" }

    var body: some View {
        let lit = held ?? chosen
        Group {
            if let columns {
                Cells(columns: columns, spacing: Space.s1, rowSpacing: Space.s1) { cells(lit) }
            } else {
                HStack(spacing: Space.s1) { cells(lit) }
            }
        }
        .background(alignment: .topLeading) { free(lit) }
        .coordinateSpace(.named(Self.area))
        .gesture(SidewaysPan(onMove: { x, y in follow(x, y) }) { _, _ in release() })
        // Under the finger the knob moves with it, unanimated; let go, it settles on its choice.
        .motion(on: lit, !Motion.still && finger == nil)
        .motion(on: finger == nil, !Motion.still && finger == nil)
        .sensoryFeedback(.selection, trigger: ticks)
        .onChange(of: chosen) { held = nil }
    }

    private func cells(_ lit: Value) -> some View {
        ForEach(values, id: \.self) { value in
            Button { choose(value) } label: {
                cell(value, value == lit)
                    .background { if value == lit, finger == nil { knob } }
                    .contentShape(Rectangle())
            }
            .buttonStyle(Press { pressed in press(value, pressed) })
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(Self.area)) } action: { spots.frames[value] = $0 }
            .accessibilityAddTraits(value == chosen ? [.isSelected] : [])
        }
    }

    private var knob: some View { Color.clear.raised(.control, .pill).matchedGeometryEffect(id: 0, in: space) }

    /// The knob under the finger, kept between the first and last choice's middles, as big as the lit one.
    @ViewBuilder private func free(_ lit: Value) -> some View {
        let middles = values.compactMap { spots.frames[$0]?.midX }
        if let finger, let spot = spots.frames[lit], let first = middles.min(), let last = middles.max() {
            knob.frame(width: spot.width, height: spot.height)
                .position(x: min(max(finger, first), last), y: spot.midY)
        }
    }

    private func press(_ value: Value, _ pressed: Bool) {
        if pressed { held = value; return }
        // A press the page's scroll took, or one on the chosen choice, lets the knob go back once its tap had its chance.
        DispatchQueue.main.asyncAfter(deadline: .now() + Motion.fast) { if !dragging, held == value { held = nil } }
    }

    private func follow(_ x: CGFloat, _ y: CGFloat) {
        dragging = true
        if columns == nil { finger = x }
        let near = values.min { a, b in distance(spots.frames[a], x, y) < distance(spots.frames[b], x, y) }
        if let near, near != (held ?? chosen) { held = near; ticks += 1 }
    }

    private func distance(_ spot: CGRect?, _ x: CGFloat, _ y: CGFloat) -> CGFloat {
        guard let spot else { return .infinity }
        return hypot(spot.midX - x, spot.midY - y)
    }

    private func release() {
        dragging = false
        finger = nil
        if let held, held != chosen { choose(held) } else { held = nil }
    }
}

/// Tells its owner when a button is pressed and let go (a knob row's choice; a card whose edge is outside its button).
struct Press: ButtonStyle {
    /// A pressed button's look: a little darker (CardStyle).
    static let dim = 0.75
    /// A disabled control, card or row (the PWA's button:disabled).
    static let faded = 0.45
    let changed: (Bool) -> Void
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.onChange(of: configuration.isPressed) { _, now in changed(now) }
    }
}

/// Cells in rows of `columns`, equal widths, all built at once. A LazyVGrid builds rows only while they're on screen and
/// can leave one blank after scrolling back to it (the picker's muscle filter on an iPhone SE).
struct Cells<Content: View>: View {
    let columns: Int
    var spacing: CGFloat = 0
    var rowSpacing: CGFloat = 0
    @ViewBuilder let content: Content

    var body: some View {
        Group(subviews: content) { cells in
            VStack(spacing: rowSpacing) {
                ForEach(Array(stride(from: 0, to: cells.count, by: columns)), id: \.self) { start in
                    // Every cell fills an equal share, a short last row kept to the columns' widths by empty ones.
                    HStack(spacing: spacing) {
                        ForEach(cells[start..<min(start + columns, cells.count)]) { $0.frame(maxWidth: .infinity) }
                        ForEach(0..<max(0, start + columns - cells.count), id: \.self) { _ in Color.clear.frame(maxWidth: .infinity) }
                    }
                }
            }
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
        // No suggestion bar: building it cost each keyboard ~100 ms before it showed (measured on the phone).
        .autocorrectionDisabled()
        .focused($focused)
        .submitLabel(.done)
        .onSubmit { submit?() }
        .padding(.horizontal, Pad.field)
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
                    row.overlay(alignment: .top) { if index > 0 { Palette.line.frame(height: Size.hairline) } }
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
/// the finger; the others step aside at once as it crosses them; let go and it moves that many places. Held near the
/// top or bottom of the page, the page scrolls (the PWA's drag does) and the row goes with it.
struct ArrangeList<Item: Identifiable, Content: View, End: View>: View {
    let items: [Item]
    let name: (Item) -> String
    /// Rows that are the same rows elsewhere (closed cards): going in and out of arranging, each glides to the other.
    var glides: Namespace.ID?
    let onMove: (_ from: Int, _ to: Int) -> Void
    @ViewBuilder let row: (Item) -> Content
    @ViewBuilder var end: (Item) -> End
    @State private var held: Item.ID?
    /// A grip under the finger; reset by SwiftUI even when the drag is cancelled, so swipe back can't stay off.
    @GestureState private var gripping = false
    @State private var finger = Finger()
    /// Places the held row has crossed: the only part of the drag that redraws the list.
    @State private var steps = 0
    /// Each row and the gap under it: a long name wraps, so rows differ (one shared step put a taller row out of place).
    @State private var heights: [Item.ID: CGFloat] = [:]
    @State private var edge = EdgeScroll()

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
                            .updating($gripping) { _, state, _ in state = true }
                            .onChanged { drag in
                                if held != item.id { held = item.id }
                                edge.drag(at: drag.location.y) { scrolled in
                                    finger.y = drag.translation.height + scrolled
                                    let now = crossed(finger.y, from: index)
                                    if now != steps { steps = now }
                                }
                            }
                            .onEnded { value in
                                edge.stop()
                                // In its new place, it slides in from where the finger left it.
                                finger.y -= span(index, steps)
                                finger.speed = value.velocity.height
                                if steps != 0 { onMove(index, index + steps) }
                                held = nil
                                steps = 0
                            })
                        .accessibilityLabel("Move \(name(item))")
                    end(item)
                }
                .pad()
                .frame(minHeight: Size.controlRow)
                .raised()
                .onGeometryChange(for: CGFloat.self) { $0.size.height + Space.s3 } action: { heights[item.id] = $0 }
                .offset(y: room(index, from, steps))
                .follow(finger, while: item.id == held)
                .matched(item.id, in: glides)
                // A fade, not .row: a transition wraps the whole row, so the uncover's clip stayed on its resting place
                // and cut away a row moved by the drag (owner, builds 70-71: rows passed over vanished).
                .transition(.opacity)
                .zIndex(item.id == held ? 1 : 0)
            }
        }
        .sensoryFeedback(.selection, trigger: steps)
        .onChange(of: gripping) { _, now in BackPan.holding = now; if !now { edge.stop() } }
        .background(ScrollFinder(edge: edge))
    }

    /// Those between the held row's place and where it would go stand aside by the held row's height.
    private func room(_ index: Int, _ from: Int?, _ steps: Int) -> CGFloat {
        guard let from, index != from else { return 0 }
        if steps > 0, index > from, index <= from + steps { return -height(from) }
        if steps < 0, index < from, index >= from + steps { return height(from) }
        return 0
    }

    private func height(_ index: Int) -> CGFloat { heights[items[index].id] ?? Size.controlRow + Space.s3 }

    /// The places the row at `index` has crossed with the finger `y` down (up when less than 0): past a row's middle.
    private func crossed(_ y: CGFloat, from index: Int) -> Int {
        let way = y < 0 ? -1 : 1
        var steps = 0, passed: CGFloat = 0
        while items.indices.contains(index + steps + way), abs(y) > passed + height(index + steps + way) / 2 {
            steps += way
            passed += height(index + steps)
        }
        return steps
    }

    /// How far the rows crossed reach, signed as `steps`.
    private func span(_ index: Int, _ steps: Int) -> CGFloat {
        let way = steps < 0 ? -1 : 1
        return CGFloat(way) * (0..<abs(steps)).reduce(0) { $0 + height(index + way * ($1 + 1)) }
    }
}

extension ArrangeList where End == EmptyView {
    init(items: [Item], name: @escaping (Item) -> String, glides: Namespace.ID? = nil, onMove: @escaping (_ from: Int, _ to: Int) -> Void,
         @ViewBuilder row: @escaping (Item) -> Content) {
        self.init(items: items, name: name, glides: glides, onMove: onMove, row: row, end: { _ in EmptyView() })
    }
}

extension View {
    /// The same row as the one with `id` elsewhere in `space` (none: on its own), so swapping one for the other glides:
    /// its place only, each keeping its own size (sized as the card, a two-line row cut its name short mid-glide).
    @ViewBuilder func matched(_ id: some Hashable, in space: Namespace.ID?) -> some View {
        if let space { matchedGeometryEffect(id: id, in: space, properties: .position) } else { self }
    }
}

/// Scrolls the page under a held row while the finger is near its top or bottom edge, every screen refresh, faster
/// the closer it is.
final class EdgeScroll: NSObject {
    /// How near the edge (pt) the page starts to scroll, and its speed (pt/s) right at the edge.
    static let zone = Size.controlRow
    static let speed: CGFloat = 900
    weak var page: UIScrollView?
    private var link: CADisplayLink?
    private var y: CGFloat = 0
    private var startOffset: CGFloat?
    private var update: (CGFloat) -> Void = { _ in }

    /// The finger at `y` (screen points): `update` gets how far the page has scrolled since the drag began, now and on
    /// each refresh it scrolls.
    func drag(at y: CGFloat, update: @escaping (CGFloat) -> Void) {
        guard let page else { update(0); return }
        if startOffset == nil { startOffset = page.contentOffset.y }
        self.y = y
        self.update = update
        update(page.contentOffset.y - (startOffset ?? 0))
        if link == nil {
            let link = CADisplayLink(target: self, selector: #selector(tick))
            link.add(to: .main, forMode: .common)
            self.link = link
        }
    }

    func stop() {
        link?.invalidate()
        link = nil
        startOffset = nil
        update = { _ in }
    }

    @objc private func tick(_ link: CADisplayLink) {
        guard let page, let start = startOffset else { return stop() }
        let shown = page.convert(page.bounds, to: nil)
        let top = shown.minY + page.adjustedContentInset.top, bottom = shown.maxY - page.adjustedContentInset.bottom
        let near = y < top + Self.zone ? -(top + Self.zone - y) : y > bottom - Self.zone ? y - (bottom - Self.zone) : 0
        guard near != 0 else { return }
        let lowest = -page.adjustedContentInset.top
        let highest = max(lowest, page.contentSize.height - page.bounds.height + page.adjustedContentInset.bottom)
        let frame = CGFloat(link.targetTimestamp - link.timestamp)
        let by: CGFloat = Self.speed * min(1, abs(near) / Self.zone) * frame * (near < 0 ? -1 : 1)
        let offset = min(highest, max(lowest, page.contentOffset.y + by))
        guard offset != page.contentOffset.y else { return }
        page.contentOffset.y = offset
        update(offset - start)
    }
}

/// Finds the page (the scroll view) a list sits in, for EdgeScroll.
private struct ScrollFinder: UIViewRepresentable {
    let edge: EdgeScroll
    func makeUIView(context: Context) -> Probe { Probe() }
    func updateUIView(_ view: Probe, context: Context) { view.edge = edge; view.find() }

    final class Probe: UIView {
        weak var edge: EdgeScroll?
        override func didMoveToWindow() { super.didMoveToWindow(); find() }
        func find() {
            var view = superview
            while let next = view, !(next is UIScrollView) { view = next.superview }
            edge?.page = view as? UIScrollView
        }
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
    /// Whether a swipe right is its own (an armed row's disarms); otherwise it's the page's swipe back (BackPan).
    var right = true
    /// Where the finger is as it moves (in this view), for a drag that follows it (KnobRow).
    var onMove: ((_ x: CGFloat, _ y: CGFloat) -> Void)? = nil
    var onEnd: (_ translation: CGFloat, _ velocity: CGFloat) -> Void

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let pan = UIPanGestureRecognizer()
        pan.delegate = context.coordinator
        context.coordinator.right = right
        return pan
    }

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator { Coordinator() }

    func updateUIGestureRecognizer(_ pan: UIPanGestureRecognizer, context: Context) { context.coordinator.right = right }

    func handleUIGestureRecognizerAction(_ pan: UIPanGestureRecognizer, context: Context) {
        if [.began, .changed].contains(pan.state), let onMove {
            let at = context.converter.localLocation // always there (only translation and velocity are optional)
            onMove(at.x, at.y)
        }
        guard [.ended, .cancelled, .failed].contains(pan.state) else { return }
        onEnd(pan.translation(in: pan.view).x, pan.velocity(in: pan.view).x)
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var right = true

        func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
            guard let pan = recognizer as? UIPanGestureRecognizer else { return false }
            let velocity = pan.velocity(in: pan.view)
            return abs(velocity.x) > abs(velocity.y) && (right || velocity.x < 0)
        }
    }
}

/// The PWA's swipe to arm: the row stays put; a swipe (or flick) left or a long press arms it (its end becomes a red
/// delete), a swipe right disarms it. While armed, a tap on the row disarms instead of opening (the caller checks).
struct SwipeToArm: ViewModifier {
    @Binding var armed: Bool
    /// How long a press arms it.
    static let hold = 0.5

    @ViewBuilder func body(content: Content) -> some View {
        if AB.noSwipe { content } else { armable(content) }
    }

    private func armable(_ content: Content) -> some View {
        content
            .contentShape(Rectangle())
            .gesture(SidewaysPan(right: armed) { x, velocity in armed = abs(velocity) > SidewaysPan.flick ? velocity < 0 : x < 0 })
            .onLongPressGesture(minimumDuration: Self.hold) { armed = true }
            .sensoryFeedback(.impact(weight: .heavy), trigger: armed) { _, now in now }
            // Its end's buttons cross-fade in place (the PWA's swapper), as it arms and disarms.
            .motion(on: armed, !Motion.still)
    }
}

extension View {
    func swipeToArm(_ armed: Binding<Bool>) -> some View { modifier(SwipeToArm(armed: armed)) }
}

extension View {
    /// What a card opens to show under its row (the PWA's .more): a hairline over it, inset like the row's text; it
    /// uncovers from the top when opened under Motion.tap.
    func more() -> some View {
        padding(.vertical, Space.s4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .top) { Palette.line.frame(height: Size.hairline) }
            .padding(.horizontal, Space.s4)
            .transition(.row)
    }
}

/// A figure's tile (a workout's Volume, a lift's Best set, the Streak): its label over the value and unit, shrunk
/// rather than cut on a narrow phone. `tight`: the unit runs on from the value ("4/30").
struct StatTile: View {
    let label: String
    let value: String
    var unit: String? = nil
    var tight = false
    var padding = Space.s3

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text(label).type(.t14).foregroundStyle(Palette.muted).lineLimit(1)
            HStack(alignment: .firstTextBaseline, spacing: tight ? 0 : Space.s1) {
                Text(value).type(.t20).monospacedDigit().foregroundStyle(Palette.text)
                if let unit { Text(unit).type(.t14).foregroundStyle(Palette.muted) }
            }
            .lineLimit(1).minimumScaleFactor(Shrink.figure)
        }
        .padding(padding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .raised()
    }
}
