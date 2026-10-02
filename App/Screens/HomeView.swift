import SwiftUI
import TrackCore

/// Home: today's date over "Ready to train", then your splits. (Starting a workout arrives in the next build.)
struct HomeView: View {
    @Environment(AppModel.self) private var model
    @Binding var settingsOpen: Bool

    var body: some View {
        let splits = model.training.splits
        Page(caption: Date.now.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()),
             title: model.training.active == nil ? "Ready to train" : "Keep going", settingsOpen: $settingsOpen) {
            if let error = model.loadError {
                Label(error, systemImage: "exclamationmark.triangle").font(.subheadline).foregroundStyle(Palette.danger)
            }
            SectionTitle(title: "Your splits", count: splits.isEmpty ? nil : splits.count)
            if splits.isEmpty {
                EmptyCard(icon: "dumbbell", title: "No splits yet",
                          detail: "Building and starting splits arrives in the next build.")
            } else {
                GroupedList {
                    ForEach(splits) { split in
                        ListRow(icon: "dumbbell", title: split.name, detail: split.summary) { EmptyView() }
                    }
                }
            }
        }
    }
}

extension Split {
    /// "3 exercises · 9 sets"
    var summary: String {
        let sets = exercises.reduce(0) { $0 + $1.sets.count }
        return "\(exercises.count) \(exercises.count == 1 ? "exercise" : "exercises") · \(sets) \(sets == 1 ? "set" : "sets")"
    }
}
