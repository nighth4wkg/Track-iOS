import SwiftUI
import TrackCore

/// History: finished workouts, newest first, grouped by week; tap one for its sets. (The calendar arrives in a later
/// build.)
struct HistoryView: View {
    @Environment(AppModel.self) private var model
    @Binding var settingsOpen: Bool

    var body: some View {
        let sessions = model.training.sessions.finished.sorted { $0.finishedAt! > $1.finishedAt! }
        let weeks = Dictionary(grouping: sessions) { weekStart($0.finishedAt!) }.sorted { $0.key > $1.key }
        Page(title: "History", settingsOpen: $settingsOpen) {
            if sessions.isEmpty {
                EmptyCard(icon: "calendar", title: "No workouts yet", detail: "Finished workouts show up here.").bareRow()
            }
            ForEach(weeks, id: \.key) { week, items in
                Section {
                    ForEach(items) { session in
                        NavigationLink { SessionDetail(session: session) } label: {
                            ListRow(icon: "checkmark", title: session.name, detail: session.summary) { EmptyView() }
                        }
                        .glassRow()
                    }
                    .onDelete { offsets in
                        let ids = offsets.map { items[$0].id }
                        model.update { $0.sessions.removeAll { ids.contains($0.id) } }
                    }
                } header: {
                    Header(title: weekTitle(week), count: items.count)
                }
            }
        }
    }

    private func weekTitle(_ start: Int) -> String {
        let now = weekStart(nowMillis())
        if start == now { return "This week" }
        if start == weekStart(now - 86_400_000) { return "Last week" }
        return "Week of " + Date(timeIntervalSince1970: Double(start) / 1000).formatted(.dateTime.month(.abbreviated).day())
    }
}

/// One finished workout: its exercises and logged sets.
struct SessionDetail: View {
    @Environment(AppModel.self) private var model
    let session: Session

    var body: some View {
        let unit = model.training.settings.unit
        List {
            Section {
                HStack(spacing: 12) {
                    detail("\(session.completedSets.count)", "sets")
                    detail(weight(session.volume, unit), unit.rawValue)
                    detail("\(session.minutes)", "min")
                }
                .bareRow()
            }
            ForEach(session.exercises) { exercise in
                Section {
                    ForEach(Array(exercise.sets.enumerated()), id: \.element.id) { index, set in
                        HStack {
                            Text(set.side.map { $0 == .left ? "L" : "R" } ?? "\(index + 1)").foregroundStyle(Palette.muted).frame(width: 28)
                            Text("\(TrainingSet.display(kg: set.kg, unit: unit)) \(unit.rawValue) × \(set.reps ?? 0)").foregroundStyle(Palette.text)
                            Spacer()
                            Text("RIR \(set.rir ?? 0)").font(.subheadline).foregroundStyle(Palette.muted)
                        }
                        .monospacedDigit().glassRow()
                    }
                } header: { Header(title: exercise.name) }
            }
            if let notes = session.notes, !notes.isEmpty {
                Section { Text(notes).foregroundStyle(Palette.text).glassRow() } header: { Header(title: "Notes") }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Backdrop())
        .navigationTitle(session.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func detail(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.title3.weight(.bold)).monospacedDigit().foregroundStyle(Palette.text)
            Text(label).font(.caption).foregroundStyle(Palette.muted)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 12).glass(radius: 16)
    }
}

extension Session {
    /// "Mon, Sep 29 · 15 sets"
    var summary: String {
        let date = Date(timeIntervalSince1970: Double(finishedAt ?? startedAt) / 1000)
        return "\(date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())) · \(count(completedSets.count, "set"))"
    }
}
