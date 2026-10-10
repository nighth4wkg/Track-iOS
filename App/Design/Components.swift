import SwiftUI
import TrackCore

/// A tab's page, laid out as on the website: a muted line over a large title, then glass cards in one scrolling
/// column, 16pt from the edges. Swipe sideways to the next or previous tab, as on the website. Above it, the
/// navigation bar keeps iOS 26's Liquid Glass: the brand, the streak and Settings each in their own bubble.
struct Page<Content: View>: View {
    @Environment(AppModel.self) private var model
    let title: String
    var caption: String?
    /// A control beside the title, as History's filter.
    var accessory: AnyView?
    /// Between the title and each card: the website's 16pt (Home's grid, 24pt).
    var spacing: CGFloat = 16
    @Binding var settingsOpen: Bool
    @ViewBuilder let content: Content
    @State private var position = ScrollPosition(edge: .top)
    @State private var shift: CGFloat = 0

    var body: some View {
        NavigationStack {
            ScrollView {
                // The website's page: 24pt from the edges, a 32pt semibold title.
                VStack(alignment: .leading, spacing: spacing) {
                    VStack(alignment: .leading, spacing: 4) {
                        if let caption { Text(caption).scaledFont(16).foregroundStyle(Palette.muted) }
                        HStack {
                            Text(title).scaledFont(32, weight: .semibold).foregroundStyle(Palette.text)
                            Spacer()
                            accessory
                        }
                    }
                    content
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
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
            // No navigation title: the page shows its own, and a hidden one was read by VoiceOver (and named the
            // back button of the pages pushed from here, "Ready to train" instead of Back).
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                let streak = model.derived("streak \(dayKey(nowMillis()))") { $0.weeklyStreak(at: nowMillis()) }
                // The brand sits on the bar itself, as on the website: no glass bubble behind it.
                ToolbarItem(placement: .topBarLeading) { Brand().fixedSize() }.sharedBackgroundVisibility(.hidden)
                // The streak shows once there is one: a 0 on day one reads as broken.
                if streak > 0 { ToolbarSpacer(.fixed, placement: .topBarLeading) }
                if streak > 0 { ToolbarItem(placement: .topBarLeading) {
                    HStack(spacing: 3) {
                        Image(systemName: "flame").foregroundStyle(Palette.streak)
                        Text("\(streak)").foregroundStyle(Palette.text)
                    }
                    .font(.subheadline.weight(.bold)).monospacedDigit().fixedSize()
                    .padding(.horizontal, 6)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(streak == 1 ? "1-week training streak" : "\(streak)-week training streak")
                } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { settingsOpen = true } label: { Image(systemName: "gearshape").foregroundStyle(Palette.text) }
                        .accessibilityLabel("Settings")
                }
            }
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
struct GlassCircleButton: View {
    let icon: String
    let label: String
    var active = false
    let action: () -> Void

    var body: some View {
        let image = Image(systemName: icon).font(.body.weight(.semibold)).contentTransition(.symbolEffect(.replace))
            .foregroundStyle(active ? Palette.accent : Palette.text)
        if #available(iOS 26, *) {
            Button(action: action) { image.frame(width: 32, height: 32) }.buttonStyle(.glass).buttonBorderShape(.circle).accessibilityLabel(label)
        } else {
            Button(action: action) { image.frame(width: 44, height: 44).glass(radius: 22, fill: Palette.control, lifted: false) }
                .buttonStyle(PressStyle()).accessibilityLabel(label)
        }
    }
}
