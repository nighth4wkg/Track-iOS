import SwiftUI
import TrackCore

/// History, as the PWA's: the filter button (a From–To range), the search, the month's calendar (tap a day to see
/// only it), then the workouts newest first, twenty at a time. Tap one for the workout.
struct HistoryView: View {
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
        let results = training.sessions.filtered(query: query, from: from, to: to)
        let filtering = !query.trimmingCharacters(in: .whitespaces).isEmpty || !from.isEmpty || !to.isEmpty
        Page(title: "History", accessory: AnyView(filterButton)) {
            VStack(alignment: .leading, spacing: 0) {
                Field(placeholder: "Search workouts or exercises", text: $query, label: "Search workouts or exercises", icon: "magnifyingglass")
                if datesOpen {
                    HStack(alignment: .top, spacing: Space.s3) {
                        DateField(label: "From", key: $from, range: Date.distantPast...(dayStart(to) ?? .now))
                        DateField(label: "To", key: $to, range: (dayStart(from) ?? .distantPast)...Date.now)
                    }
                    .padding(.top, Space.s3)
                    .transition(.opacity)
                }
                HistoryCalendar(month: $month, from: $from, to: $to, sessions: training.sessions.finished).padding(.top, Space.s3)
                list(results, filtering: filtering, unit: training.settings.unit).padding(.top, Space.s6)
            }
        }
        .animation(.smooth(duration: Motion.standard), value: datesOpen)
        .sensoryFeedback(.selection, trigger: from + to)
        .onChange(of: query + from + to) { shown = Self.page }
    }

    private var filterButton: some View {
        RoundButton(icon: "line.3.horizontal.decrease", label: datesOpen ? "Hide date range" : "Filter by date") { datesOpen.toggle() }
    }

    @ViewBuilder private func list(_ results: [Session], filtering: Bool, unit: TrackCore.Settings.Unit) -> some View {
        HStack {
            Text(filtering ? count(results.count, "result") : "Recent").type(.t20).foregroundStyle(Palette.text)
            Spacer()
            if filtering {
                Button("Clear") { query = ""; from = ""; to = "" }.buttonStyle(SecondaryButtonStyle(hug: true))
            }
        }
        .frame(minHeight: Size.control)
        if results.isEmpty {
            Text(model.training.sessions.finished.isEmpty ? "Finish a workout and it shows up here." : "No workouts match. Try another name or date.")
                .type(.t14).foregroundStyle(Palette.muted).padding(.top, Space.s2)
        } else {
            LazyVStack(spacing: Space.s3) {
                ForEach(results.prefix(shown)) { session in
                    Button { model.history = session } label: { HistoryRow(session: session, unit: unit) }.buttonStyle(PressStyle())
                }
            }
            .padding(.top, Space.s2)
            if results.count > shown {
                Button("Show more") { shown += Self.page }.buttonStyle(SecondaryButtonStyle()).padding(.top, Space.s3)
            }
        }
    }
}

/// From or To: the day as the app writes dates ("Oct 24, 2026", or "Any day") on a SUNK field; tap it for a calendar.
private struct DateField: View {
    let label: String
    @Binding var key: String
    let range: ClosedRange<Date>
    @State private var picking = false

    var body: some View {
        let day = dayStart(key)
        VStack(alignment: .leading, spacing: Space.s2) {
            Text(label).type(.t14).foregroundStyle(Palette.muted)
            Button { picking = true } label: {
                Text(day?.formatted(.gregorian.month(.abbreviated).day().year()) ?? "Any day")
                    .scaledFont(TextStyle.t16.size).foregroundStyle(day == nil ? Palette.muted : Palette.text).lineLimit(1)
                    .padding(.horizontal, Space.s3)
                    .frame(maxWidth: .infinity, minHeight: Size.control, alignment: .leading)
                    .sunk()
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(label), \(day?.formatted(.gregorian.month(.wide).day().year()) ?? "any day")")
            .popover(isPresented: $picking) {
                DatePicker(label, selection: Binding(get: { day ?? min(max(range.lowerBound, .now), range.upperBound) },
                                                     set: { key = dayKey(millis($0)); picking = false }),
                           in: range, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .environment(\.calendar, Calendars.local)
                    .padding(Space.s4)
                    .presentationCompactAdaptation(.popover)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

/// A workout in the list, as the PWA's: its date tile (weekday over the day), its name over time · sets · volume.
private struct HistoryRow: View {
    let session: Session
    let unit: TrackCore.Settings.Unit

    var body: some View {
        let date = Date(timeIntervalSince1970: Double(session.finishedAt!) / 1000)
        HStack(spacing: Space.s3) {
            VStack(spacing: 0) {
                Text(date.formatted(.gregorian.weekday(.abbreviated))).type(.t12).foregroundStyle(Palette.muted)
                Text(date.formatted(.gregorian.day())).type(.t16).monospacedDigit().foregroundStyle(Palette.text)
            }
            .frame(width: Size.tile, height: Size.tile)
            .raised(.control, .inner)
            VStack(alignment: .leading, spacing: 0) {
                Text(session.name).type(.t16).foregroundStyle(Palette.text)
                Text("\(session.minutes) min · \(count(session.loggedCount, "set")) · \(weight(session.volume, unit)) \(unit.rawValue)")
                    .type(.t14).foregroundStyle(Palette.muted)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.system(size: IconSize.medium, weight: .semibold)).foregroundStyle(Palette.muted)
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .raised()
        .contentShape(Rectangle())
    }
}

/// "2026-10-24" as the start of that day.
private func dayStart(_ key: String) -> Date? {
    let parts = key.split(separator: "-").compactMap { Int($0) }
    guard parts.count == 3 else { return nil }
    return Calendars.local.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
}
