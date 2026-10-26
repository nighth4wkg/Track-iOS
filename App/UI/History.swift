import SwiftUI
import TrackCore

/// History (the PWA's): the filter button (a From–To range), the search, the month's calendar (tap a day to see only
/// it), then the workouts newest first, twenty at a time. Tap one for the workout.
struct HistoryScreen: View {
    @Environment(AppModel.self) private var model
    @State private var query = ""
    @State private var from = ""
    @State private var to = ""
    @State private var datesOpen = false
    @State private var shown = Self.page
    @State private var month = HistoryCalendar.monthStart(.now)
    private static let page = 20

    var body: some View {
        let training = model.training
        // Kept until the workouts or the search change: History stays alive behind the other tabs, and every set
        // logged would otherwise sort the whole history again.
        let results = model.derived("history", at: [query, from, to]) { $0.filtered(query: query, from: from, to: to) }
        let filtering = !query.trimmingCharacters(in: .whitespaces).isEmpty || !from.isEmpty || !to.isEmpty
        TabPage {
            TabHead(title: "History") {
                RoundButton(icon: .filter, label: datesOpen ? "Hide date range" : "Filter by date") { datesOpen.toggle() }
            }
            Field(placeholder: "Search workouts or exercises", text: $query, label: "Search workouts or exercises", icon: .search)
                .padding(.top, Space.s4)
            if datesOpen {
                HStack(alignment: .top, spacing: Space.s3) {
                    DateField(label: "From", key: $from, range: Date.distantPast...(dayStart(to) ?? .now))
                    DateField(label: "To", key: $to, range: (dayStart(from) ?? .distantPast)...Date.now)
                }
                .padding(.top, Space.s3)
            }
            HistoryCalendar(month: $month, from: $from, to: $to, trained: model.derived("trained days") { Set($0.finished.compactMap { $0.finishedAt.map { dayKey($0) } }) })
                .padding(.top, Space.s3)
            list(results, filtering: filtering, unit: training.settings.unit).padding(.top, Space.s6)
        }
        .sensoryFeedback(.selection, trigger: from + to)
        .onChange(of: query + from + to) { shown = Self.page }
    }

    private func list(_ results: [Session], filtering: Bool, unit: TrackCore.Settings.Unit) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Space.s3) {
                Text(filtering ? count(results.count, "result") : "Recent").type(.t20).foregroundStyle(Palette.text).accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
                if filtering {
                    Button("Clear") { query = ""; from = ""; to = "" }.buttonStyle(SecondaryStyle(hug: true))
                }
            }
            .frame(minHeight: Size.control)
            if results.isEmpty {
                Text(model.derived("any finished") { $0.finished.isEmpty } ? "Finish a workout and it shows up here." : "No workouts match. Try another name or date.")
                    .type(.t14).foregroundStyle(Palette.muted).padding(.top, Space.s2)
            } else {
                LazyVStack(spacing: Space.s3) {
                    ForEach(results.prefix(shown)) { session in
                        Button { model.open(.session(session.id)) } label: { HistoryRow(session: session, unit: unit) }.buttonStyle(CardStyle())
                    }
                }
                .padding(.top, Space.s2)
                if results.count > shown {
                    Button("Show more") { shown += Self.page }.buttonStyle(SecondaryStyle()).padding(.top, Space.s3)
                }
            }
        }
    }
}

/// From or To: the day as the app writes dates ("Oct 24, 2026", or "Any day") on a SUNK field; tap it for a calendar
/// on a sheet (choosing a day closes it).
private struct DateField: View {
    @Environment(AppModel.self) private var model
    let label: String
    @Binding var key: String
    let range: ClosedRange<Date>

    var body: some View {
        let day = dayStart(key)
        VStack(alignment: .leading, spacing: Space.s2) {
            Text(label).type(.t14).foregroundStyle(Palette.muted)
            Button { model.present(DateSheet(label: label, key: $key, range: range)) } label: {
                Text(day?.formatted(.gregorian.month(.abbreviated).day().year()) ?? "Any day")
                    .type(.t16).fontWeight(.regular).foregroundStyle(day == nil ? Palette.muted : Palette.text).lineLimit(1)
                    .padding(.horizontal, Space.s3)
                    .frame(maxWidth: .infinity, minHeight: Size.control, alignment: .leading)
                    .sunk()
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(label), \(day?.formatted(.gregorian.month(.wide).day().year()) ?? "any day")")
        }
        .frame(maxWidth: .infinity)
    }
}

/// The calendar for a From or To day.
private struct DateSheet: View {
    @Environment(\.closeSheet) private var close
    let label: String
    @Binding var key: String
    let range: ClosedRange<Date>

    var body: some View {
        SheetFrame(title: label) {
            DatePicker(label, selection: Binding(get: { dayStart(key) ?? min(max(range.lowerBound, .now), range.upperBound) },
                                                 set: { key = dayKey(millis($0)); close() }),
                       in: range, displayedComponents: .date)
                .datePickerStyle(.graphical)
                .labelsHidden()
                .tint(Palette.accent)
                .environment(\.calendar, Calendars.local)
                .padding(.top, Space.s3)
        }
    }
}

/// A workout in the list: its date tile (weekday over the day), its name over time · sets · volume.
private struct HistoryRow: View {
    let session: Session
    let unit: TrackCore.Settings.Unit

    var body: some View {
        let date = Date(timeIntervalSince1970: Double(session.finishedAt ?? session.startedAt) / 1000)
        HStack(spacing: Space.s3) {
            VStack(spacing: 0) {
                Text(date.formatted(.gregorian.weekday(.abbreviated))).type(.t12).foregroundStyle(Palette.muted)
                Text(date.formatted(.gregorian.day())).type(.t16).monospacedDigit().foregroundStyle(Palette.text)
            }
            .frame(width: Size.tile, height: Size.tile)
            .raised(.control, .inner)
            // VoiceOver read the tile as "Mon, 26"; it says the whole date instead.
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(date.formatted(.gregorian.weekday(.wide).month(.wide).day()))
            VStack(alignment: .leading, spacing: 0) {
                Text(session.name).type(.t16).foregroundStyle(Palette.text).multilineTextAlignment(.leading)
                Text("\(session.minutes) min" + dot + count(session.loggedCount, "set") + dot + "\(weight(session.volume, unit)) \(unit.rawValue)")
                    .type(.t14).foregroundStyle(Palette.muted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Icon.next.image(IconSize.medium).foregroundStyle(Palette.muted)
        }
        .pad()
        .raised()
        .contentShape(Rectangle())
    }
}

/// The training calendar: the month over a Monday-first grid with the neighbouring months' days greyed. Today sits on
/// a raised tile in green; a dot under a day means you trained. Tap a day to see only it; again, all.
struct HistoryCalendar: View {
    @Binding var month: Date
    @Binding var from: String
    @Binding var to: String
    /// The days with a finished workout ("2026-10-25").
    let trained: Set<String>

    var body: some View {
        let calendar = Calendars.local
        let today = dayKey(nowMillis())
        let lead = (calendar.component(.weekday, from: month) + 5) % 7
        let length = calendar.range(of: .day, in: .month, for: month)?.count ?? 30
        let start = calendar.date(byAdding: .day, value: -lead, to: month) ?? month
        let columns = calendar.weekdaySymbols.count
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(spacing: Space.s2) {
                Text(month.formatted(.gregorian.month(.wide).year())).type(.t16).foregroundStyle(Palette.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
                RoundButton(icon: .back, label: "Previous month", size: IconSize.medium) { step(-1) }
                RoundButton(icon: .next, label: "Next month", size: IconSize.medium) { step(1) }
                    .disabled(month >= Self.monthStart(Date())) // no workouts ahead of this month
            }
            Cells(columns: columns) {
                ForEach(Array(["M", "T", "W", "T", "F", "S", "S"].enumerated()), id: \.offset) { _, letter in
                    Text(letter).type(.t12).foregroundStyle(Palette.muted)
                }
            }
            .accessibilityHidden(true)
            Cells(columns: columns, rowSpacing: Space.s1) {
                ForEach(0..<(lead + length + 6) / 7 * 7, id: \.self) { offset in
                    let date = calendar.date(byAdding: .day, value: offset, to: start) ?? start
                    let key = dayKey(millis(date))
                    let picked = from == key && to == key
                    let isToday = key == today
                    let inMonth = calendar.isDate(date, equalTo: month, toGranularity: .month)
                    Button {
                        guard key <= today else { return } // a day still ahead has nothing to show
                        from = picked ? "" : key; to = picked ? "" : key
                    } label: {
                        VStack(spacing: Space.s1) {
                            Text(date.formatted(.gregorian.day())).type(.t14).fontWeight(isToday ? .bold : nil).monospacedDigit()
                                .foregroundStyle(!inMonth || key > today ? Palette.faint : isToday ? Palette.accent : Palette.text)
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
                    .accessibilityRemoveTraits(key > today ? .isButton : []) // a day ahead does nothing on tap
                }
            }
        }
        .pad()
        .raised()
    }

    static func monthStart(_ date: Date) -> Date { Calendars.local.dateInterval(of: .month, for: date)?.start ?? date }

    private func step(_ months: Int) {
        month = Calendars.local.date(byAdding: .month, value: months, to: month) ?? month
    }
}

/// Today's day on the raised control tile.
private struct TodayTile: ViewModifier {
    let on: Bool

    func body(content: Content) -> some View {
        if on { content.raised(.control, .inner) } else { content }
    }
}

/// "2026-10-24" as the start of that day.
private func dayStart(_ key: String) -> Date? {
    let parts = key.split(separator: "-").compactMap { Int($0) }
    guard parts.count == 3 else { return nil }
    return Calendars.local.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
}
