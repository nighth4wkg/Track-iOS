import SwiftUI
import TrackCore

/// One finished workout: its totals, exercises and logged sets.
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
                    detail(duration(session.minutes), "time")
                }
                .bareRow()
            }
            ForEach(session.exercises) { exercise in
                Section {
                    Text(exercise.name).font(.title3.weight(.semibold)).foregroundStyle(Palette.text).glassRow()
                    ForEach(Array(exercise.sets.enumerated()), id: \.element.id) { index, set in
                        HStack {
                            Text(set.side.map { $0 == .left ? "L" : "R" } ?? "\(index + 1)").foregroundStyle(Palette.muted).frame(width: 28)
                            Text("\(TrainingSet.display(kg: set.kg, unit: unit)) \(unit.rawValue) × \(set.reps ?? 0)").foregroundStyle(Palette.text)
                            Spacer()
                            Text("RIR \(set.rir ?? 0)").font(.subheadline).foregroundStyle(Palette.muted)
                        }
                        .monospacedDigit().glassRow()
                    }
                }
            }
            if let notes = session.notes, !notes.isEmpty {
                Section { Text(notes).foregroundStyle(Palette.text).glassRow() } header: { SmallHeader(title: "Notes") }
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
