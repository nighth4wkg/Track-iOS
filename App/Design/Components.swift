import SwiftUI
import TrackCore

/// A tab's page, as the PWA's: its own header (on Home the brand and Settings, then the date over the title; on the
/// others the title and one control), then cards in one scrolling column, 16 from the edges, clear of the nav pill.
/// Swipe sideways to the next or previous tab. No navigation bar: the page draws its own header, as the PWA.
struct Page<Content: View>: View {
    @Environment(AppModel.self) private var model
    let title: String
    var caption: String?
    /// A control beside the title, as History's filter.
    var accessory: AnyView?
    /// Between the header and each card.
    var spacing: CGFloat = Space.s4
    /// Home only: the brand and Settings above the title.
    var settingsOpen: Binding<Bool>?
    @ViewBuilder let content: Content
    @State private var position = ScrollPosition(edge: .top)
    @State private var shift: CGFloat = 0

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: spacing) {
                    VStack(alignment: .leading, spacing: Space.s2) {
                        if let settingsOpen {
                            HStack {
                                Brand()
                                Spacer()
                                RoundButton(icon: "gearshape", label: "Settings") { settingsOpen.wrappedValue = true }
                            }
                        }
                        VStack(alignment: .leading, spacing: 0) {
                            if let caption { Text(caption).type(.t14).foregroundStyle(Palette.muted) }
                            HStack(spacing: Space.s3) {
                                Text(title).type(.t32).foregroundStyle(Palette.text)
                                Spacer()
                                accessory
                            }
                            .frame(minHeight: Size.control)
                        }
                    }
                    content
                }
                .padding(.horizontal, Space.s4)
                .padding(.top, Space.s4)
                // Clear of the nav pill, which floats over the home indicator's strip (floatingBottom).
                .padding(.bottom, Size.nav + Space.s4 * 2 - homeIndicator)
                .frame(maxWidth: Measure.page)
                .frame(maxWidth: .infinity)
                .offset(x: shift)
                // Slides only: fading the whole page made it one offscreen layer, repainted every frame of the slide.
                .opacity(LookTest.old ? 1 - Double(abs(shift) / Space.s3) : 1)
            }
            .scrollPosition($position)
            .onAppear(perform: arrive)
            .scrollDismissesKeyboard(.interactively)
            .gesture(HorizontalPan(sharesTouches: true, onChange: { _ in }, onEnd: { x, velocity in
                guard let step = HorizontalPan.tabStep(x, velocity), let index = AppTab.allCases.firstIndex(of: model.tab) else { return }
                let next = index + step
                if AppTab.allCases.indices.contains(next) { model.tab = AppTab.allCases[next] }
            }))
            .background(Backdrop())
            .toolbar(.hidden, for: .navigationBar)
            .toolbarVisibility(.hidden, for: .tabBar)
        }
    }

    /// Each time the tab is switched to (not back from one of its pages): from the top, sliding in from the side it
    /// was swiped from.
    private func arrive() {
        guard model.arrivedTab != model.tab else { return }
        model.arrivedTab = model.tab
        position.scrollTo(edge: .top)
        shift = Space.s3 * model.tabStep
        DispatchQueue.main.async { withAnimation(.smooth(duration: Motion.fast)) { shift = 0 } }
    }
}

/// A round icon button in Liquid Glass (iOS 26), or the Sheen glass before it.
struct RoundButton: View {
    let icon: String
    let label: String
    var active = false
    /// An icon colour of its own (red for a delete).
    var tint: Color?
    var size = IconSize.regular
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: size, weight: .semibold)).contentTransition(.symbolEffect(.replace))
                .foregroundStyle(tint ?? (active ? Palette.accent : Palette.text))
                .frame(width: Size.control, height: Size.control)
                .raised(.control, .circle)
        }
        .buttonStyle(PressStyle()).accessibilityLabel(label)
    }
}

/// The PWA's Arrange mode (ArrangeRow and Grip): each row on its own card with a grip at its end. Drag the grip and
/// the row follows the finger while the others slide aside to make room; let go and it moves that many places.
struct ArrangeList<Item: Identifiable, Row: View, End: View>: View {
    let items: [Item]
    /// What the grip is read as: "Move Push".
    let name: (Item) -> String
    let onMove: (_ from: Int, _ to: Int) -> Void
    @ViewBuilder let row: (Item) -> Row
    /// After the grip (a split's exercise: its trash).
    @ViewBuilder var end: (Item) -> End
    @State private var held: Item.ID?
    @State private var drag: CGFloat = 0
    /// One row and the gap under it: how far a drag goes per place.
    @State private var step = Size.row

    var body: some View {
        let from = items.firstIndex { $0.id == held }
        let steps = from.map { start in max(-start, min(items.count - 1 - start, Int((drag / step).rounded()))) } ?? 0
        VStack(spacing: Space.s3) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                HStack(spacing: Space.s3) {
                    row(item)
                    Spacer(minLength: 0)
                    Image(systemName: "line.3.horizontal").font(.system(size: IconSize.medium, weight: .semibold)).foregroundStyle(Palette.text)
                        .frame(width: Size.control, height: Size.control).raised(.control, .circle)
                        .contentShape(Circle())
                        .gesture(DragGesture(coordinateSpace: .global)
                            .onChanged { held = item.id; drag = $0.translation.height }
                            .onEnded { _ in
                                withAnimation(.smooth(duration: Motion.fast)) {
                                    if steps != 0 { onMove(index, index + steps) }
                                    held = nil
                                    drag = 0
                                }
                            })
                        .accessibilityLabel("Move \(name(item))")
                    end(item)
                }
                .padding(Space.s4)
                .frame(minHeight: Size.control + Space.s4 * 2)
                .raised()
                .onGeometryChange(for: CGFloat.self) { $0.size.height + Space.s3 } action: { step = $0 }
                .offset(y: room(index, from, steps)).animation(.smooth(duration: Motion.fast), value: steps)
                .offset(y: item.id == held ? drag : 0)
                .zIndex(item.id == held ? 1 : 0)
            }
        }
        .sensoryFeedback(.selection, trigger: steps)
    }

    /// The others make room: those between the held row's place and where it would go shift one place its way.
    private func room(_ index: Int, _ from: Int?, _ steps: Int) -> CGFloat {
        guard let from, index != from else { return 0 }
        if steps > 0, index > from, index <= from + steps { return -step }
        if steps < 0, index < from, index >= from + steps { return step }
        return 0
    }
}

extension ArrangeList where End == EmptyView {
    init(items: [Item], name: @escaping (Item) -> String, onMove: @escaping (_ from: Int, _ to: Int) -> Void, @ViewBuilder row: @escaping (Item) -> Row) {
        self.init(items: items, name: name, onMove: onMove, row: row, end: { _ in EmptyView() })
    }
}

/// A page pushed over a tab, as the PWA's bare pages: the back button beside its title (and a line under it), one
/// control at the end, then its cards. The nav pill steps aside while it's up.
struct SubPage<Content: View, Trailing: View>: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    var subtitle: String?
    @ViewBuilder var trailing: Trailing
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: Space.s3) {
                    RoundButton(icon: "chevron.left", label: "Back") { dismiss() }
                    VStack(alignment: .leading, spacing: 0) {
                        Text(title).type(.t20).foregroundStyle(Palette.text).lineLimit(1)
                        if let subtitle { Text(subtitle).type(.t14).foregroundStyle(Palette.muted).lineLimit(1) }
                    }
                    .accessibilityAddTraits(.isHeader)
                    Spacer(minLength: 0)
                    trailing
                }
                content
            }
            .padding(.horizontal, Space.s4)
            .padding(.top, Space.s4)
            .padding(.bottom, Space.s6)
            .frame(maxWidth: Measure.page)
            .frame(maxWidth: .infinity)
        }
        .background(Backdrop())
        .toolbar(.hidden, for: .navigationBar)
        .toolbarVisibility(.hidden, for: .tabBar) // a pushed page mustn't bring iOS's tab bar back
    }
}

extension SubPage where Trailing == EmptyView {
    init(title: String, subtitle: String? = nil, @ViewBuilder content: () -> Content) {
        self.init(title: title, subtitle: subtitle, trailing: { EmptyView() }, content: content)
    }
}

/// A row of choices, as the PWA's Seg: a SUNK pill track with one raised knob under the chosen one, shared with the
/// nav pill's behaviour (owner: every pill works the same): a press brings the knob to the finger at once; drag it and
/// it follows (across rows too, in a wrapped one), the choice under it lit with a tick each; letting go chooses the
/// nearest. Short shows only each choice's first letter (D W M), still read out in full.
struct Seg<Value: Hashable>: View {
    let label: String
    let options: [(value: Value, text: String)]
    @Binding var value: Value
    var short = false
    /// Small, inside a row (kg / lb, log sets).
    var compact = false
    /// Wrapped into rows of this many, as the PWA's .seg.wrap (the picker's muscles).
    var columns: Int?
    /// Each choice's place in the track.
    @State private var cells: [Int: CGRect] = [:]
    /// The choice under the finger while it's down.
    @State private var near: Int?
    /// The knob's place while dragged; nil sits it on its choice.
    @State private var dragAt: CGPoint?
    /// Decided by the first move: sideways is the knob's drag, up or down a scroll (nil: not moved yet).
    @State private var sideways: Bool?
    private static var space: String { "seg" }

    var body: some View {
        let chosen = options.firstIndex { $0.value == value }
        let shown = near ?? chosen
        Group {
            if let columns {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Space.s1), count: columns), spacing: Space.s1) { choices(shown) }
            } else {
                HStack(spacing: Space.s1) { choices(shown) }
            }
        }
        .background(alignment: .topLeading) {
            if let shown, let cell = cells[shown] {
                Color.clear.raised(.control, .pill)
                    .frame(width: cell.width, height: cell.height)
                    .offset(x: (dragAt ?? cell.origin).x, y: (dragAt ?? cell.origin).y)
                    // It glides when the choice changes; its track being laid out (first, or resized) just places it.
                    .animation(dragAt == nil ? .smooth(duration: Motion.fast) : nil, value: shown)
            }
        }
        .coordinateSpace(.named(Self.space))
        .simultaneousGesture(DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.space))
            .onChanged(follow)
            .onEnded { _ in
                SwipeZones.held = false
                if sideways != false, let near { value = options[near].value }
                withAnimation(.smooth(duration: Motion.fast)) { near = nil; dragAt = nil }
                sideways = nil
            })
        .padding(Space.s1)
        .sunk(columns == nil ? .pill : .card)
        .fixedSize(horizontal: short || compact, vertical: false)
        .sensoryFeedback(.selection, trigger: shown)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(label)
    }

    private func choices(_ shown: Int?) -> some View {
        ForEach(Array(options.enumerated()), id: \.element.value) { index, option in
            Text(short ? String(option.text.prefix(1)) : option.text)
                .type(.t14).fontWeight(.semibold).lineLimit(1)
                .foregroundStyle(index == shown ? Palette.text : Palette.muted)
                .frame(maxWidth: .infinity, minHeight: compact ? Size.compact : Size.segment)
                .frame(minWidth: short || compact ? Size.cell : nil)
                .contentShape(Rectangle())
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(Self.space)) } action: { cells[index] = $0 }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(option.text)
                .accessibilityAddTraits(option.value == value ? [.isButton, .isSelected] : .isButton)
                .accessibilityAction { value = option.value }
        }
    }

    /// The finger down or moving: the nearest choice lights up; once it has gone sideways the knob rides under it,
    /// kept within the track. Up or down first is a scroll: the knob goes back.
    private func follow(_ drag: DragGesture.Value) {
        guard sideways != false, !cells.isEmpty, let first = cells.values.first else { return }
        SwipeZones.held = true
        if sideways == nil, hypot(drag.translation.width, drag.translation.height) >= Space.s2 {
            sideways = abs(drag.translation.width) > abs(drag.translation.height)
            if sideways == false {
                SwipeZones.held = false
                withAnimation(.smooth(duration: Motion.fast)) { near = nil; dragAt = nil }
                return
            }
        }
        let size = first.size
        let xs = cells.values.map(\.minX), ys = cells.values.map(\.minY)
        let x = min(max(drag.location.x - size.width / 2, xs.min()!), xs.max()!)
        let y = min(max(drag.location.y - size.height / 2, ys.min()!), ys.max()!)
        let index = cells.min { hypot($0.value.minX - x, $0.value.minY - y) < hypot($1.value.minX - x, $1.value.minY - y) }!.key
        if near != index { near = index }
        if sideways == true { dragAt = CGPoint(x: x, y: y) }
    }
}

/// Rows on one card, as the PWA's .card of .row: a hairline between rows. Each row pads itself (Row does), so a
/// whole row is its button.
struct RowCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) {
            Group(subviews: content) { rows in
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    row.overlay(alignment: .top) { if index > 0 { Palette.hairline.frame(height: 1) } }
                }
            }
        }
        .raised()
        .clipShape(Corner.card.shape)
    }
}

/// A row, as the PWA's .row: its name, then what sits at its end; 16 all round, a row tall at least.
struct Row<Trailing: View>: View {
    let title: String
    var tint = Palette.text
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: Space.s3) {
            Text(title).type(.t16).foregroundStyle(tint).lineLimit(1)
            Spacer(minLength: 0)
            trailing
        }
        .padding(.horizontal, Space.s4)
        .padding(.vertical, Space.s3)
        .frame(minHeight: Size.row)
        .contentShape(Rectangle())
    }
}

extension Row where Trailing == RowValue {
    /// A row with a value at its end ("1:30 min"), and a chevron when it opens something.
    init(title: String, tint: Color = Palette.text, value: String, color: Color = Palette.muted, chevron: Bool = false) {
        self.init(title: title, tint: tint) { RowValue(text: value, color: color, chevron: chevron) }
    }
}

/// A row's end: a value in t14, and a chevron when the row opens something.
struct RowValue: View {
    let text: String
    var color = Palette.muted
    var chevron = false

    var body: some View {
        HStack(spacing: Space.s2) {
            if !text.isEmpty { Text(text).type(.t14).monospacedDigit().foregroundStyle(color).lineLimit(1) }
            if chevron { Image(systemName: "chevron.right").font(.system(size: IconSize.small, weight: .semibold)).foregroundStyle(Palette.muted) }
        }
    }
}
