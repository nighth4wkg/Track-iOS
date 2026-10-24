import SwiftUI
import TrackCore

/// The training calendar, as the PWA's: the month over a Monday-first grid with the neighbouring months' days greyed.
/// Today sits on a raised tile in green; a dot under a day means you trained. Tap a day to see only it; again, all.
struct HistoryCalendar: View {
    @Binding var month: Date
    @Binding var from: String
    @Binding var to: String
    let sessions: [Session]

    var body: some View {
        let calendar = Calendars.local
        let trained = Set(sessions.map { dayKey($0.finishedAt!) })
        let today = dayKey(nowMillis())
        let lead = (calendar.component(.weekday, from: month) + 5) % 7
        let length = calendar.range(of: .day, in: .month, for: month)!.count
        let start = calendar.date(byAdding: .day, value: -lead, to: month)!
        let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(spacing: Space.s2) {
                Text(month.formatted(.gregorian.month(.wide).year())).type(.t16).foregroundStyle(Palette.text)
                Spacer()
                RoundButton(icon: "chevron.left", label: "Previous month", size: IconSize.medium) { step(-1) }
                RoundButton(icon: "chevron.right", label: "Next month", size: IconSize.medium) { step(1) }
            }
            LazyVGrid(columns: columns, spacing: 0) {
                ForEach(Array(["M", "T", "W", "T", "F", "S", "S"].enumerated()), id: \.offset) { _, letter in
                    Text(letter).type(.t12).foregroundStyle(Palette.muted)
                }
            }
            .accessibilityHidden(true)
            LazyVGrid(columns: columns, spacing: Space.s1) {
                ForEach(0..<(lead + length + 6) / 7 * 7, id: \.self) { offset in
                    let date = calendar.date(byAdding: .day, value: offset, to: start)!
                    let key = dayKey(millis(date))
                    let picked = from == key && to == key
                    let isToday = key == today
                    let inMonth = calendar.isDate(date, equalTo: month, toGranularity: .month)
                    Button { from = picked ? "" : key; to = picked ? "" : key } label: {
                        VStack(spacing: Space.s1) {
                            Text(date.formatted(.gregorian.day())).type(.t14).fontWeight(isToday ? .bold : nil).monospacedDigit()
                                .foregroundStyle(!inMonth ? Palette.faint : isToday ? Palette.accent : Palette.text)
                            Circle().fill(trained.contains(key) ? Palette.accent : .clear).frame(width: Size.dot, height: Size.dot)
                        }
                        .frame(width: Size.tile, height: Size.tile)
                        .background { if picked { Corner.inner.shape.fill(Palette.greenPick) } }
                        .modifier(TodayTile(on: isToday && !picked))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(date.formatted(.gregorian.month(.wide).day()) + (trained.contains(key) ? ", trained" : ""))
                    .accessibilityAddTraits(picked ? .isSelected : [])
                }
            }
        }
        .padding(Space.s4)
        .raised()
    }

    static func monthStart(_ date: Date) -> Date { Calendars.local.dateInterval(of: .month, for: date)!.start }

    private func step(_ months: Int) {
        month = Calendars.local.date(byAdding: .month, value: months, to: month)!
    }
}

/// Today's day on the raised control tile.
private struct TodayTile: ViewModifier {
    let on: Bool

    func body(content: Content) -> some View {
        if on { content.raised(.control, .inner) } else { content }
    }
}
