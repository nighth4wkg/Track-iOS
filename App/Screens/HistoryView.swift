import SwiftUI
import TrackCore

/// History, as on the website: the filter button (a From–To range), the search (Clear appears while any filter is
/// on), the month's calendar, then workouts newest first in weeks, twenty at a time. Each row has its date tile,
/// sets · time · volume and a PR chip when it broke a record; tap it for the workout, swipe it left to delete it.
struct HistoryView: View {
    @Environment(AppModel.self) private var model
    @Binding var settingsOpen: Bool
    @State private var query = ""
    @State private var month = HistoryCalendar.monthStart(.now)
    @State private var day: String?
    @State private var datesOpen = false
    @State private var from: Date?
    @State private var to: Date?
    @State private var shownCount = 20

    var body: some View {
        let training = model.training
        let all = training.sessions.finished.sorted { $0.finishedAt! > $1.finishedAt! }
        let range = (day ?? from.map { dayKey(millis($0)) } ?? "", day ?? to.map { dayKey(millis($0)) } ?? "")
        let shown = training.sessions.filtered(query: query, from: range.0, to: range.1)
        let filtering = !query.trimmingCharacters(in: .whitespaces).isEmpty || day != nil || from != nil || to != nil
        let weeks = Dictionary(grouping: shown.prefix(shownCount)) { weekStart($0.finishedAt!) }.sorted { $0.key > $1.key }
        let recordSessions = Set(training.sessions.improvements.map(\.after.sessionId))
        Page(title: "History", accessory: all.isEmpty ? nil : AnyView(filterButton), settingsOpen: $settingsOpen) {
            if !all.isEmpty {
                search(filtering: filtering, label: "\(shown.count) of \(count(all.count, "workout"))")
                if datesOpen { dateRange.transition(.opacity.combined(with: .move(edge: .top))) }
                HistoryCalendar(month: $month, day: $day, sessions: all)
            }
            if all.isEmpty {
                EmptyCard(icon: "calendar", title: "Your story starts here.", detail: "Finish a workout to save your sets, weights, and reps here.")
                Button { model.tab = .home } label: { Label("Go to your splits", systemImage: "arrow.up.right").labelStyle(TrailingIcon()) }
                    .buttonStyle(PrimaryButtonStyle())
            } else if shown.isEmpty {
                EmptyCard(icon: "calendar", title: "No workouts found.", detail: "Try another exercise or date range.")
                Button("Clear filters") { clear() }.buttonStyle(SecondaryButtonStyle())
            }
            ForEach(weeks, id: \.key) { week, items in
                VStack(alignment: .leading, spacing: 8) {
                    SmallHeader(title: weekTitle(week))
                    GlassList {
                        ForEach(items) { session in
                            SwipeToDelete(onDelete: { model.deleteWorkout(session) }) {
                                Button { model.history = session } label: {
                                    HistoryRow(session: session, unit: training.settings.unit, record: recordSessions.contains(session.id))
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(PressStyle())
                            }
                        }
                    }
                }
            }
            if shown.count > shownCount {
                Button("Show more workouts (\(shown.count - shownCount) remaining)") { withAnimation(.smooth) { shownCount += 20 } }
                    .buttonStyle(SecondaryButtonStyle())
            }
        }
        .animation(.smooth(duration: 0.3), value: datesOpen)
        .sensoryFeedback(.selection, trigger: day)
        .onChange(of: query) { shownCount = 20 }
    }

    private var filterButton: some View {
        GlassCircleButton(icon: "line.3.horizontal.decrease", label: datesOpen ? "Hide date range" : "Filter by date",
                          active: from != nil || to != nil) { withAnimation(.smooth(duration: 0.3)) { datesOpen.toggle() } }
    }

    private func search(filtering: Bool, label: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(Palette.muted)
            TextField("Search workouts or exercises", text: $query).submitLabel(.search)
            if filtering {
                Button("Clear") { clear() }.font(.subheadline.weight(.semibold)).foregroundStyle(Palette.accent)
                    .accessibilityLabel("Clear filters, \(label)")
            }
        }
        .padding(.horizontal, 14).frame(minHeight: 48)
        .glass(radius: 14, fill: Palette.input, lifted: false)
    }

    /// From and To, each a date or "Any".
    private var dateRange: some View {
        GlassList {
            dateRow("From", $from, in: Date.distantPast...(to ?? .now))
            dateRow("To", $to, in: (from ?? .distantPast)...Date.now)
        }
    }

    private func dateRow(_ label: String, _ value: Binding<Date?>, in range: ClosedRange<Date>) -> some View {
        HStack {
            Text(label).foregroundStyle(Palette.text)
            Spacer()
            if let date = value.wrappedValue {
                DatePicker(label, selection: Binding(get: { date }, set: { new in withAnimation(.smooth) { value.wrappedValue = new; shownCount = 20 } }),
                           in: range, displayedComponents: .date)
                    .labelsHidden()
                    .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .trailing)))
                Button { withAnimation(.smooth) { value.wrappedValue = nil } } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Palette.muted) }
                    .accessibilityLabel("Any \(label.lowercased()) date")
            } else {
                Button("Any") {
                    withAnimation(.smooth) { value.wrappedValue = min(max(range.lowerBound, Calendars.local.date(byAdding: .month, value: -1, to: .now)!), range.upperBound) }
                }
                    .font(.subheadline.weight(.semibold)).foregroundStyle(Palette.text)
                    .padding(.horizontal, 12).frame(minHeight: 36).glass(radius: 12, fill: Palette.control, lifted: false)
                    .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .trailing)))
            }
        }
        .frame(minHeight: 44)
    }

    private func clear() {
        withAnimation(.smooth) { query = ""; day = nil; from = nil; to = nil; shownCount = 20 }
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
                Text("\(count(session.completedSets.count, "set")) · \(trainingDuration(session.minutes)) · \(weight(session.volume, unit)) \(unit.rawValue)")
                    .font(.subheadline).foregroundStyle(Palette.muted).lineLimit(1).minimumScaleFactor(0.85)
            }
            Spacer(minLength: 4)
            if record {
                HStack(spacing: 3) { Image(systemName: "trophy"); Text("PR") }
                    .font(.caption.weight(.bold)).foregroundStyle(Palette.record).fixedSize()
                    .padding(.horizontal, 8).padding(.vertical, 4).glass(radius: 12, fill: Palette.control, lifted: false)
            }
            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Palette.muted)
        }
    }
}
