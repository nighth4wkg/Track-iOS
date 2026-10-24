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
                .padding(.bottom, Size.nav + Space.s4 * 2)
                .frame(maxWidth: Measure.page)
                .frame(maxWidth: .infinity)
                .offset(x: shift)
                .opacity(1 - Double(abs(shift)) / 12)
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
        }
    }

    /// Each time the tab is switched to (not back from one of its pages): from the top, sliding in from the side it
    /// was swiped from.
    private func arrive() {
        guard model.arrivedTab != model.tab else { return }
        model.arrivedTab = model.tab
        position.scrollTo(edge: .top)
        shift = 12 * model.tabStep
        DispatchQueue.main.async { withAnimation(.easeOut(duration: Motion.fast)) { shift = 0 } }
    }
}

/// Rows on one glass card, split by the website's hairline: 16pt in from both sides, full width between them
/// (app/styles/list-group.css).
struct GlassList<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) {
            Group(subviews: content) { rows in
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    if index > 0 { Rectangle().fill(Palette.hairline).frame(height: 1).padding(.horizontal, 16) }
                    row.padding(.horizontal, 16).padding(.vertical, 10)
                }
            }
        }
        .glass()
        .clipShape(RoundedRectangle(cornerRadius: Measure.card, style: .continuous))
    }
}

/// A section heading as on the website: "Your splits 2" with optional round buttons at the end.
struct SectionHeading<Trailing: View>: View {
    let title: String
    var count: Int?
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Text(title).font(.title3.weight(.bold)).foregroundStyle(Palette.text)
            if let count { Text("\(count)").font(.subheadline).foregroundStyle(Palette.muted) }
            Spacer()
            trailing
        }
        .padding(.top, 8)
    }
}

extension SectionHeading where Trailing == EmptyView {
    init(title: String, count: Int? = nil) { self.init(title: title, count: count) { EmptyView() } }
}

/// The website's select: the value and a chevron, opening the system menu (Liquid Glass).
struct GlassMenu<Value: Hashable>: View {
    let selection: Value
    let options: [(Value, String)]
    let onSelect: (Value) -> Void

    var body: some View {
        Menu {
            ForEach(options.indices, id: \.self) { index in
                let (value, label) = options[index]
                Button { onSelect(value) } label: {
                    if value == selection { Label(label, systemImage: "checkmark") } else { Text(label) }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text(options.first { $0.0 == selection }?.1 ?? "").lineLimit(1)
                Image(systemName: "chevron.down").font(.caption.weight(.bold))
            }
            .font(.body).foregroundStyle(Palette.text)
            .frame(minHeight: 40).contentShape(Rectangle())
        }
        .sensoryFeedback(.selection, trigger: selection)
    }
}

/// A small muted heading over a group, as History's "This week" or "Sep 14 – 20".
struct SmallHeader: View {
    let title: String

    var body: some View {
        Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(Palette.muted).padding(.leading, 4).padding(.top, 8)
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
struct ArrangeList<Item: Identifiable, Row: View>: View {
    let items: [Item]
    /// What the grip is read as: "Move Push".
    let name: (Item) -> String
    let onMove: (_ from: Int, _ to: Int) -> Void
    @ViewBuilder let row: (Item) -> Row
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

/// A page pushed over a tab, as the PWA's bare pages: the back button beside its title (and a line under it), one
/// control at the end, then its cards. The nav pill steps aside while it's up.
struct SubPage<Content: View, Trailing: View>: View {
    @Environment(AppModel.self) private var model
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
        .onAppear { model.pushed += 1 }
        .onDisappear { model.pushed -= 1 }
    }
}

extension SubPage where Trailing == EmptyView {
    init(title: String, subtitle: String? = nil, @ViewBuilder content: () -> Content) {
        self.init(title: title, subtitle: subtitle, trailing: { EmptyView() }, content: content)
    }
}

/// A row of choices, as the PWA's Seg: a SUNK pill track with a raised knob that slides under the chosen one. Short
/// shows only each choice's first letter (D W M), still read out in full.
struct Seg<Value: Hashable>: View {
    let label: String
    let options: [(value: Value, text: String)]
    @Binding var value: Value
    var short = false
    @Namespace private var knob

    var body: some View {
        HStack(spacing: Space.s1) {
            ForEach(options, id: \.value) { option in
                let on = option.value == value
                Button { value = option.value } label: {
                    Text(short ? String(option.text.prefix(1)) : option.text)
                        .type(.t14).fontWeight(.semibold).lineLimit(1)
                        .foregroundStyle(on ? Palette.text : Palette.muted)
                        .frame(maxWidth: .infinity, minHeight: Size.segment)
                        .frame(minWidth: short ? Size.cell : nil)
                        .background {
                            if on { Color.clear.raised(.control, .pill).matchedGeometryEffect(id: "knob", in: knob) }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(option.text)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(Space.s1)
        .sunk(.pill)
        .fixedSize(horizontal: short, vertical: false)
        .animation(.smooth(duration: Motion.fast), value: value)
        .sensoryFeedback(.selection, trigger: value)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(label)
    }
}
