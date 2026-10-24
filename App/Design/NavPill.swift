import SwiftUI

/// The four tabs on the PWA's floating pill (ui/parts.tsx Nav): RAISED, 16 above the screen's bottom edge (the
/// home indicator's strip is thin enough to float over, as the PWA's --clear works out), with a knob that slides
/// under the chosen tab. The chosen tab is green with a bolder icon.
struct NavPill: View {
    @Environment(AppModel.self) private var model
    @State private var width: CGFloat = 0

    private static let tabs: [(tab: AppTab, label: String, icon: String)] = [
        (.home, "Home", "house"), (.history, "History", "calendar"), (.progress, "Progress", "chart.bar"), (.rank, "Rank", "rosette"),
    ]

    var body: some View {
        let index = CGFloat(Self.tabs.firstIndex { $0.tab == model.tab } ?? 0)
        let cell = max(0, (width - Space.s1 * CGFloat(Self.tabs.count + 1)) / CGFloat(Self.tabs.count))
        HStack(spacing: Space.s1) {
            ForEach(Self.tabs, id: \.tab) { item in
                let on = item.tab == model.tab
                Button { model.tab = item.tab } label: {
                    VStack(spacing: Space.s1 / 2) {
                        Image(systemName: item.icon).font(.system(size: IconSize.logo, weight: on ? .bold : .medium))
                            .frame(height: IconSize.logo)
                        Text(item.label).type(.t12)
                    }
                    .foregroundStyle(on ? Palette.accent : Palette.muted)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(Space.s1)
        .frame(height: Size.nav)
        .background(alignment: .leading) {
            Color.clear.raised(.control, .pill)
                .frame(width: cell, height: Size.nav - Space.s1 * 2)
                .offset(x: Space.s1 + index * (cell + Space.s1))
                .animation(.smooth(duration: Motion.fast), value: model.tab)
        }
        .raised(.nav, .pill)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .frame(maxWidth: Size.navWidth)
        .padding(.horizontal, Space.s4)
        .padding(.bottom, Space.s4)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Main")
    }
}
