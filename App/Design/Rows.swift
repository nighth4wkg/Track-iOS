import SwiftUI
import TrackCore

/// A small label pill, as the PWA's .badge: green on a green wash ("Up next", "Next"), or muted on a faint wash
/// (`plain`) for a count like "0/3".
struct Badge: View {
    let text: String
    var plain = false

    var body: some View {
        Text(text).type(.t12).fontWeight(.bold).monospacedDigit().lineLimit(1)
            .foregroundStyle(plain ? Palette.muted : Palette.accent)
            .padding(.horizontal, Space.s2).padding(.vertical, Space.s1)
            .background(plain ? Palette.wash : Palette.greenWash, in: Capsule())
    }
}

/// This week's training days against the goal, as the PWA's week ring: the count over "days" inside, "This week"
/// under it.
struct WeekRing: View {
    let done: Int
    let goal: Int

    var body: some View {
        let fraction = min(1, Double(done) / Double(max(goal, 1)))
        VStack(spacing: Space.s1) {
            ZStack {
                Circle().stroke(Palette.input, lineWidth: Size.ringStroke)
                Circle().trim(from: 0, to: fraction).stroke(Palette.primary, style: StrokeStyle(lineWidth: Size.ringStroke, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.smooth(duration: Motion.slow), value: fraction)
                VStack(spacing: 0) {
                    HStack(alignment: .firstTextBaseline, spacing: 0) {
                        Text("\(done)").type(.t28).monospacedDigit()
                        Text("/\(goal)").type(.t14).foregroundStyle(Palette.muted)
                    }
                    Text(goal == 1 ? "day" : "days").type(.t12).foregroundStyle(Palette.muted)
                }
                .foregroundStyle(Palette.text)
            }
            .frame(width: Size.weekRing, height: Size.weekRing)
            Text("This week").type(.t12).foregroundStyle(Palette.muted)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(done) of \(count(goal, "training day")) this week")
    }
}

/// A total weight in the chosen unit, whole numbers with grouping: "10,805".
func weight(_ kg: Double, _ unit: TrackCore.Settings.Unit) -> String {
    (kg * (unit == .lb ? Limits.poundsPerKilogram : 1)).formatted(.number.precision(.fractionLength(0)))
}

/// "1 exercise", "3 sets".
func count(_ value: Int, _ noun: String) -> String { "\(value) \(noun)\(value == 1 ? "" : "s")" }

extension FormatStyle where Self == Date.FormatStyle {
    /// Dates as on the website: always the Gregorian calendar, so an iPhone set to the Buddhist one doesn't show
    /// "2569 BE". The words and order still follow the iPhone's language.
    /// In English, as the website writes dates ("Sep 23", "Sunday, Oct 4"), whatever the phone's region.
    static var gregorian: Date.FormatStyle { Date.FormatStyle(locale: Locale(identifier: "en"), calendar: Calendars.local, timeZone: .current) }
}
