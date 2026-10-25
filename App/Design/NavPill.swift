import SwiftUI

/// The four tabs on the PWA's floating pill (ui/parts.tsx Nav): RAISED, 16 above the screen's bottom edge (the
/// home indicator's strip is thin enough to float over, as the PWA's --clear works out), with a knob that slides
/// under the chosen tab. The chosen tab is green with a bolder icon. As the PWA's knob: a press brings the knob to
/// the finger at once; drag it sideways and it follows (the tab under it lights up, a tick each), and letting go
/// chooses the nearest.
struct NavPill: View {
    @Environment(AppModel.self) private var model
    @State private var width: CGFloat = 0
    /// The tab under the finger while it's down.
    @State private var near: Int?
    /// The knob's place while dragged; nil sits it on its tab.
    @State private var dragX: CGFloat?

    private static let tabs: [(tab: AppTab, label: String, icon: String)] = [
        (.home, "Home", "house"), (.history, "History", "calendar"), (.progress, "Progress", "chart.bar"), (.rank, "Rank", "rosette"),
    ]

    var body: some View {
        let chosen = Self.tabs.firstIndex { $0.tab == model.tab } ?? 0
        let cell = max(0, (width - Space.s1 * CGFloat(Self.tabs.count + 1)) / CGFloat(Self.tabs.count))
        let spot = { (index: Int) in Space.s1 + CGFloat(index) * (cell + Space.s1) }
        HStack(spacing: Space.s1) {
            ForEach(Array(Self.tabs.enumerated()), id: \.element.tab) { index, item in
                let on = index == (near ?? chosen)
                VStack(spacing: Space.s1 / 2) {
                    Image(systemName: item.icon).font(.system(size: IconSize.logo, weight: on ? .bold : .medium))
                        .frame(height: IconSize.logo)
                    Text(item.label).type(.t12)
                }
                .foregroundStyle(on ? Palette.accent : Palette.muted)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(index == chosen ? [.isButton, .isSelected] : .isButton)
                .accessibilityAction { model.tab = item.tab }
            }
        }
        .padding(Space.s1)
        .frame(height: Size.nav)
        .background(alignment: .leading) {
            Color.clear.raised(.control, .pill)
                .frame(width: cell, height: Size.nav - Space.s1 * 2)
                .offset(x: dragX ?? spot(near ?? chosen))
                .animation(dragX == nil ? .smooth(duration: Motion.fast) : nil, value: dragX ?? spot(near ?? chosen))
        }
        .raised(.nav, .pill)
        .contentShape(Capsule())
        .gesture(DragGesture(minimumDistance: 0)
            .onChanged { drag in
                guard cell > 0 else { return }
                // Sideways past a small step claims it as a drag; until then it's a press on the tab below.
                let x = min(max(drag.location.x - cell / 2, spot(0)), spot(Self.tabs.count - 1))
                if dragX != nil || abs(drag.translation.width) >= Space.s2 { dragX = x }
                let index = Int(((x - Space.s1) / (cell + Space.s1)).rounded())
                if near != index { near = index }
            }
            .onEnded { _ in
                if let near { model.tab = Self.tabs[near].tab }
                withAnimation(.smooth(duration: Motion.fast)) { dragX = nil; near = nil }
            })
        .sensoryFeedback(.selection, trigger: near) { old, now in old != nil && now != nil }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .frame(maxWidth: Size.navWidth)
        .padding(.horizontal, Space.s4)
        .padding(.bottom, Space.s4)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Main")
    }
}
