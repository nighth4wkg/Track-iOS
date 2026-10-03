import SwiftUI
import TrackCore

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

extension FormatStyle where Self == Date.FormatStyle {
    /// Dates as on the website: always the Gregorian calendar, so an iPhone set to the Buddhist one doesn't show
    /// "2569 BE". The words and order still follow the iPhone's language.
    static var gregorian: Date.FormatStyle { Date.FormatStyle(calendar: Calendars.local, timeZone: .current) }
}
