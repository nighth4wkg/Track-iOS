import SwiftUI
import TrackCore

/// A tab's page: the system navigation bar (a large title that shrinks as you scroll, the brand at the leading edge,
/// Settings at the trailing edge) over an inset grouped list whose groups are glass cards on the Sheen backdrop.
/// The grouped list gives iOS's own swipe actions and reordering.
struct Page<Content: View>: View {
    let title: String
    var caption: String?
    @Binding var settingsOpen: Bool
    @ViewBuilder let content: Content

    var body: some View {
        NavigationStack {
            List {
                if let caption {
                    Text(caption).font(.subheadline).foregroundStyle(Palette.muted)
                        .listRowBackground(Color.clear).listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
                }
                content
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .listSectionSpacing(20)
            .background(Backdrop())
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Brand() }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { settingsOpen = true } label: { Image(systemName: "gearshape") }
                        .accessibilityLabel("Settings")
                }
            }
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

/// One row: a 44pt glass tile, a name over one line of detail, then the row's end.
struct ListRow<Trailing: View>: View {
    var icon: String?
    var mark = false
    let title: String
    let detail: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if mark { TrackMark(size: 20) } else if let icon { Image(systemName: icon).font(.body.weight(.semibold)) }
            }
            .foregroundStyle(Palette.text)
            .frame(width: 44, height: 44).glass(radius: 12, fill: Palette.control, lifted: false)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline).foregroundStyle(Palette.text).lineLimit(1)
                Text(detail).font(.subheadline).foregroundStyle(Palette.muted).lineLimit(1)
            }
            Spacer(minLength: 8)
            trailing
        }
        .padding(.vertical, 4)
    }
}

/// A small glass pill: a status like "Next", or a count like "0/3".
struct Chip: View {
    let text: String
    var accent = false

    var body: some View {
        Text(text).font(.caption.weight(.bold)).monospacedDigit()
            .foregroundStyle(accent ? Palette.accent : Palette.muted)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .glass(radius: 12, fill: Palette.control, lifted: false)
    }
}

/// A calm empty state on a glass card.
struct EmptyCard: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon).font(.title2).foregroundStyle(Palette.muted)
                .frame(width: 56, height: 56).glass(radius: 16, fill: Palette.control, lifted: false)
            Text(title).font(.headline).foregroundStyle(Palette.text)
            Text(detail).font(.subheadline).foregroundStyle(Palette.muted).multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .glass()
    }
}

/// This week's workouts against the goal, as the ring on Home.
struct WeekRing: View {
    let done: Int
    let goal: Int

    var body: some View {
        let fraction = min(1, Double(done) / Double(max(goal, 1)))
        VStack(spacing: 6) {
            ZStack {
                Circle().stroke(Palette.input, lineWidth: 8)
                Circle().trim(from: 0, to: fraction).stroke(Palette.primary, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.smooth(duration: 0.6), value: fraction)
                HStack(alignment: .firstTextBaseline, spacing: 1) {
                    Text("\(done)").font(.title.weight(.bold)).monospacedDigit()
                    Text("/\(goal)").font(.subheadline).foregroundStyle(Palette.muted)
                }
                .foregroundStyle(Palette.text)
            }
            .frame(width: 84, height: 84)
            Text("This week").font(.caption).foregroundStyle(Palette.muted)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(done) of \(goal) workouts this week")
    }
}

/// A total weight in the chosen unit, whole numbers with grouping: "10,805".
func weight(_ kg: Double, _ unit: TrackCore.Settings.Unit) -> String {
    (kg * (unit == .lb ? 2.2046226218 : 1)).formatted(.number.precision(.fractionLength(0)))
}

/// "1 exercise", "3 sets".
func count(_ value: Int, _ noun: String) -> String { "\(value) \(noun)\(value == 1 ? "" : "s")" }
