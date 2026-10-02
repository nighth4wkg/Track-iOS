import SwiftUI
import TrackCore

/// History, as on the website: a search, the month's calendar (trained days lit; tap one to show just that day),
/// then the workouts newest first in weeks, each with its date tile, sets · time · volume, and a PR chip when it
/// broke a record. Swipe a workout left to delete it.
struct HistoryView: View {
    @Environment(AppModel.self) private var model
    @Binding var settingsOpen: Bool
    @State private var query = ""
    @State private var month = Calendars.local.dateInterval(of: .month, for: .now)!.start
    @State private var day: String?

    var body: some View {
        let training = model.training
        let all = training.sessions.finished.sorted { $0.finishedAt! > $1.finishedAt! }
        let words = Catalog.simplify(query).split(separator: " ")
        let shown = all.filter { session in
            (day == nil || dayKey(session.finishedAt!) == day)
                && (words.isEmpty || words.allSatisfy { word in
                    ([session.name] + session.exercises.map(\.name)).contains { Catalog.simplify($0).contains(word) }
                })
        }
        let weeks = Dictionary(grouping: shown) { weekStart($0.finishedAt!) }.sorted { $0.key > $1.key }
        let recordSessions = Set(training.sessions.improvements.map(\.after.sessionId))
        Page(title: "History", settingsOpen: $settingsOpen) {
            Section {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(Palette.muted)
                    TextField("Search workouts or exercises", text: $query).submitLabel(.search)
                }
                .padding(.horizontal, 14).frame(minHeight: 48)
                .glass(radius: 14, fill: Palette.input, lifted: false).bareRow()
            }
            Section { CalendarCard(month: $month, day: $day, sessions: all).bareRow() }
            if shown.isEmpty {
                Section {
                    EmptyCard(icon: "calendar", title: all.isEmpty ? "No workouts yet" : "Nothing matches",
                              detail: all.isEmpty ? "Finished workouts show up here." : "Try another search or day.").bareRow()
                }
            }
            ForEach(weeks, id: \.key) { week, items in
                Section {
                    ForEach(items) { session in
                        NavigationLink { SessionDetail(session: session) } label: {
                            HistoryRow(session: session, unit: training.settings.unit, record: recordSessions.contains(session.id))
                        }
                        .glassRow()
                    }
                    .onDelete { offsets in
                        let ids = offsets.map { items[$0].id }
                        model.update { $0.sessions.removeAll { ids.contains($0.id) } }
                    }
                } header: { SmallHeader(title: weekTitle(week)) }
            }
        }
        .sensoryFeedback(.selection, trigger: day)
    }

    /// "This week", "Last week", or the week's range ("Sep 14 – 20", "Aug 31 – Sep 6").
    private func weekTitle(_ start: Int) -> String {
        let now = weekStart(nowMillis())
        if start == now { return "This week" }
        if start == weekStart(now - 86_400_000) { return "Last week" }
        let first = Date(timeIntervalSince1970: Double(start) / 1000)
        let last = Calendars.local.date(byAdding: .day, value: 6, to: first)!
        let sameMonth = Calendars.local.component(.month, from: first) == Calendars.local.component(.month, from: last)
        return "\(first.formatted(.dateTime.month(.abbreviated).day())) – \(last.formatted(sameMonth ? .dateTime.day() : .dateTime.month(.abbreviated).day()))"
    }
}

/// A workout in the list: a date tile (day and weekday), its name over sets · time · volume, a PR chip.
private struct HistoryRow: View {
    let session: Session
    let unit: TrackCore.Settings.Unit
    let record: Bool

    var body: some View {
        let date = Date(timeIntervalSince1970: Double(session.finishedAt!) / 1000)
        HStack(spacing: 12) {
            VStack(spacing: 0) {
                Text(date.formatted(.dateTime.day())).font(.headline).monospacedDigit()
                Text(date.formatted(.dateTime.weekday(.abbreviated))).font(.caption2).foregroundStyle(Palette.muted)
            }
            .foregroundStyle(Palette.text).frame(width: 44, height: 44).glass(radius: 12, fill: Palette.control, lifted: false)
            VStack(alignment: .leading, spacing: 2) {
                Text(session.name).font(.headline).foregroundStyle(Palette.text).lineLimit(1)
                Text("\(count(session.completedSets.count, "set")) · \(duration(session.minutes)) · \(weight(session.volume, unit)) \(unit.rawValue)")
                    .font(.subheadline).foregroundStyle(Palette.muted).lineLimit(1)
            }
            Spacer(minLength: 8)
            if record {
                Label("PR", systemImage: "trophy").font(.caption.weight(.bold)).foregroundStyle(Palette.ranks[4])
                    .padding(.horizontal, 8).padding(.vertical, 4).glass(radius: 12, fill: Palette.control, lifted: false)
            }
        }
        .padding(.vertical, 2)
    }
}

/// "1h 2m", "45m".
func duration(_ minutes: Int) -> String { minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m" : "\(minutes)m" }

/// The month as on the website: its name over workouts · time, ‹ › to change month, and a Monday-first grid where
/// trained days are lit (today's filled in the accent). Tapping a trained day shows only it; tapping again, all.
private struct CalendarCard: View {
    @Binding var month: Date
    @Binding var day: String?
    let sessions: [Session]

    var body: some View {
        let calendar = Calendars.local
        let inMonth = sessions.filter { calendar.isDate(Date(timeIntervalSince1970: Double($0.finishedAt!) / 1000), equalTo: month, toGranularity: .month) }
        let trained = Set(sessions.map { dayKey($0.finishedAt!) })
        let days = calendar.range(of: .day, in: .month, for: month)!.count
        let lead = (calendar.component(.weekday, from: month) + 5) % 7
        let today = dayKey(nowMillis())
        let isCurrent = calendar.isDate(month, equalTo: .now, toGranularity: .month)
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(month.formatted(.dateTime.month(.wide).year(calendar.isDate(month, equalTo: .now, toGranularity: .year) ? .omitted : .defaultDigits)))
                        .font(.headline).foregroundStyle(Palette.text)
                    Text("\(count(inMonth.count, "workout")) · \(duration(inMonth.reduce(0) { $0 + $1.minutes }))")
                        .font(.subheadline).foregroundStyle(Palette.muted)
                }
                Spacer()
                GlassCircleButton(icon: "chevron.left", label: "Previous month") { step(-1) }
                GlassCircleButton(icon: "chevron.right", label: "Next month") { step(1) }.disabled(isCurrent).opacity(isCurrent ? 0.4 : 1)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7), spacing: 6) {
                ForEach(["M", "T", "W", "T", "F", "S", "S"].indices, id: \.self) { index in
                    Text(["M", "T", "W", "T", "F", "S", "S"][index]).font(.caption.weight(.bold)).foregroundStyle(Palette.muted)
                }
                ForEach(0..<lead, id: \.self) { _ in Color.clear.frame(height: 36) }
                ForEach(1...days, id: \.self) { number in
                    let date = calendar.date(byAdding: .day, value: number - 1, to: month)!
                    let key = dayKey(millis(date))
                    let lit = trained.contains(key)
                    Button { if lit { withAnimation(.smooth) { day = day == key ? nil : key } } } label: {
                        Text("\(number)").font(.subheadline.weight(lit ? .bold : .regular)).monospacedDigit()
                            .foregroundStyle(key == today && lit ? Palette.primaryText : lit ? Palette.text : Palette.muted.opacity(0.6))
                            .frame(maxWidth: .infinity, minHeight: 36)
                            .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(key == today && lit ? Palette.primary : lit ? Palette.control : Palette.input.opacity(0.5)))
                            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(day == key ? Palette.accent : .clear, lineWidth: 2))
                    }
                    .buttonStyle(.plain)
                    .disabled(!lit)
                    .accessibilityLabel(date.formatted(date: .complete, time: .omitted) + (lit ? ", trained" : ""))
                }
            }
        }
        .padding(16)
        .glass()
    }

    private func step(_ months: Int) {
        withAnimation(.smooth) {
            month = Calendars.local.date(byAdding: .month, value: months, to: month)!
            day = nil
        }
    }
}

extension Session {
    /// "Mon, Sep 29 · 15 sets"
    var summary: String {
        let date = Date(timeIntervalSince1970: Double(finishedAt ?? startedAt) / 1000)
        return "\(date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())) · \(count(completedSets.count, "set"))"
    }
}
