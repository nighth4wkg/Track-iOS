import SwiftUI
import TrackCore

/// History: finished workouts, newest first. (The calendar and workout details arrive in a later build.)
struct HistoryView: View {
    @Environment(AppModel.self) private var model
    @Binding var settingsOpen: Bool

    var body: some View {
        let sessions = model.training.sessions.sorted { ($0.finishedAt ?? 0) > ($1.finishedAt ?? 0) }
        Page(caption: nil, title: "History", settingsOpen: $settingsOpen) {
            if sessions.isEmpty {
                EmptyCard(icon: "calendar", title: "No workouts yet", detail: "Finished workouts show up here.")
            } else {
                GroupedList {
                    ForEach(sessions) { session in
                        ListRow(icon: "checkmark", title: session.name, detail: session.summary) { EmptyView() }
                    }
                }
            }
        }
    }
}

extension Session {
    /// "Mon, Sep 29 · 15 sets"
    var summary: String {
        let date = Date(timeIntervalSince1970: Double(finishedAt ?? startedAt) / 1000)
        let sets = exercises.reduce(0) { $0 + $1.sets.filter(\.done).count }
        return "\(date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())) · \(sets) \(sets == 1 ? "set" : "sets")"
    }
}
