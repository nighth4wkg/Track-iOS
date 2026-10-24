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
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: IconSize.regular, weight: .semibold)).contentTransition(.symbolEffect(.replace))
                .foregroundStyle(active ? Palette.accent : Palette.text)
                .frame(width: Size.control, height: Size.control)
                .raised(.control, .circle)
        }
        .buttonStyle(PressStyle()).accessibilityLabel(label)
    }
}
