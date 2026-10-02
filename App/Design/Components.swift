import SwiftUI
import TrackCore

/// A tab's page, laid out as on the website: a muted line over a large title, then glass cards in one scrolling
/// column, 16pt from the edges. Above it, the navigation bar keeps iOS 26's Liquid Glass: the brand and streak in one
/// bubble, Settings in another.
struct Page<Content: View>: View {
    @Environment(AppModel.self) private var model
    let title: String
    var caption: String?
    /// A control beside the title, as History's filter.
    var accessory: AnyView?
    @Binding var settingsOpen: Bool
    @ViewBuilder let content: Content

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        if let caption { Text(caption).font(.body).foregroundStyle(Palette.muted) }
                        HStack {
                            Text(title).font(.system(size: 34, weight: .bold)).tracking(-0.5).foregroundStyle(Palette.text)
                            Spacer()
                            accessory
                        }
                    }
                    .padding(.bottom, 8)
                    content
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 32)
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Backdrop())
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) { Color.clear.frame(width: 1, height: 1).accessibilityHidden(true) }
                ToolbarItem(placement: .topBarLeading) {
                    HStack(spacing: 10) {
                        Brand()
                        let streak = model.training.sessions.weeklyStreak(at: nowMillis())
                        HStack(spacing: 3) {
                            Image(systemName: "flame").foregroundStyle(Palette.streak)
                            Text("\(streak)").foregroundStyle(Palette.text)
                        }
                        .font(.subheadline.weight(.bold)).monospacedDigit()
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(streak == 1 ? "1-week training streak" : "\(streak)-week training streak")
                    }
                    .fixedSize()
                    .padding(.horizontal, 4)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { settingsOpen = true } label: { Image(systemName: "gearshape").foregroundStyle(Palette.text) }
                        .accessibilityLabel("Settings")
                }
            }
        }
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
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
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

/// The website's glass select: the value and a chevron in a glass pill, opening the system menu (Liquid Glass).
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
            .font(.subheadline.weight(.semibold)).foregroundStyle(Palette.text)
            .padding(.horizontal, 12).frame(minHeight: 40)
            .glass(radius: 12, fill: Palette.control, lifted: false)
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
        let image = Image(systemName: icon).font(.body.weight(.semibold))
            .foregroundStyle(active ? Palette.accent : Palette.text)
        if #available(iOS 26, *) {
            Button(action: action) { image.frame(width: 28, height: 28) }.buttonStyle(.glass).buttonBorderShape(.circle).accessibilityLabel(label)
        } else {
            Button(action: action) { image.frame(width: 44, height: 44).glass(radius: 22, fill: Palette.control, lifted: false) }
                .buttonStyle(PressStyle()).accessibilityLabel(label)
        }
    }
}

extension View {
    /// A list row on its group's glass card.
    func glassRow() -> some View {
        listRowBackground(Rectangle().fill(Palette.card))
            .listRowSeparatorTint(Palette.hairline)
    }

    /// A row that draws its own card (heroes, tiles): no list background or insets.
    func bareRow() -> some View {
        listRowBackground(Color.clear).listRowInsets(EdgeInsets()).listRowSeparator(.hidden)
    }
}

/// A section header in the website's style: a title with an optional count, not the small caps of iOS.
struct Header: View {
    let title: String
    var count: Int?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title).font(.title3.weight(.semibold)).foregroundStyle(Palette.text)
            if let count { Text("\(count)").font(.subheadline).foregroundStyle(Palette.muted) }
        }
        .textCase(nil)
        .padding(.leading, -4)
    }
}
