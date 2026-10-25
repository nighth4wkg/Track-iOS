import SwiftUI
import TrackCore

/// After Finish (the PWA's Complete): "Nice workout!" over its name and day, the XP card (the level ring, +XP, Level up,
/// what's left to the next level and its bar), Duration · Volume · Streak tiles, each exercise's best set (new records
/// marked), and Continue docked at the bottom, back to Home as the PWA.
struct CompleteScreen: View {
    @Environment(AppModel.self) private var model
    let finished: Finished

    var body: some View {
        let sessions = model.training.sessions
        let unit = model.training.settings.unit
        if let session = sessions.first(where: { $0.id == finished.id }), let at = session.finishedAt {
            let level = Experience.progress(of: sessions)
            let before = Dictionary(sessions.filter { $0.id != session.id }.personalRecords.map { ($0.name, $0.kg) }, uniquingKeysWith: max)
            let bests = session.exercises.compactMap { exercise -> (name: String, set: TrainingSet, fresh: Bool)? in
                guard let set = exercise.sets.filter(\.isValid).max(by: { ($0.kg ?? 0, $0.reps ?? 0) < ($1.kg ?? 0, $1.reps ?? 0) }) else { return nil }
                return (exercise.name, set, before[exercise.name].map { (set.kg ?? 0) > $0 } ?? false)
            }
            DeepPage {
                Text("Workout complete").type(.t14).foregroundStyle(Palette.muted)
                Text("Nice workout!").type(.t32).foregroundStyle(Palette.text).accessibilityAddTraits(.isHeader)
                Text(session.name + dot + Date(timeIntervalSince1970: Double(at) / 1000).formatted(.gregorian.weekday(.wide).month(.abbreviated).day()))
                    .type(.t14).foregroundStyle(Palette.muted)
                xpCard(level).padding(.top, Space.s4)
                HStack(spacing: Space.s3) {
                    tile("Duration", "\(session.minutes)", "min")
                    tile("Volume", weight(session.volume, unit), unit.rawValue)
                    tile("Streak", "\(sessions.weeklyStreak(at: at))", "wk")
                }
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, Space.s3)
                if !bests.isEmpty {
                    Text("Best sets").type(.t20).foregroundStyle(Palette.text).padding(.top, Space.s6).accessibilityAddTraits(.isHeader)
                    RowCard {
                        ForEach(bests, id: \.name) { best in
                            Row(title: best.name) {
                                if best.fresh { Badge(text: "New best") }
                                Text("\(TrainingSet.display(kg: best.set.kg ?? 0, unit: unit)) \(unit.rawValue) × \(best.set.reps ?? 0)")
                                    .type(.t14).monospacedDigit().foregroundStyle(Palette.text)
                            }
                        }
                    }
                    .padding(.top, Space.s2)
                }
                // Room for the dock, so the last card scrolls clear of it.
                Color.clear.frame(height: Size.primary + Space.s4 - homeIndicator)
            }
            .overlay(alignment: .bottom) {
                Button("Continue") { model.finished = nil; model.go(.home) }.buttonStyle(PrimaryStyle())
                    .padding(.horizontal, Space.s4)
                    .frame(maxWidth: Size.column)
                    .floatingBottom()
                    .floatingBar(Size.primary)
            }
            .sensoryFeedback(.success, trigger: finished.id)
        } else {
            DeepPage {
                Text("Workout saved.").type(.t16).foregroundStyle(Palette.text)
                Button("Continue") { model.finished = nil; model.go(.home) }.buttonStyle(PrimaryStyle()).padding(.top, Space.s4)
            }
        }
    }

    /// The level ring with the level, +XP, and the bar to the next level.
    private func xpCard(_ level: Experience.Progress) -> some View {
        let fraction = Double(level.current) / Double(max(1, level.required))
        return HStack(spacing: Space.s4) {
            Ring(value: fraction, size: Rings.level.size, stroke: Rings.level.stroke, label: "Level \(level.level)") {
                VStack(spacing: 0) {
                    Text("Level").type(.t12).foregroundStyle(Palette.muted)
                    Text("\(level.level)").type(.t28).monospacedDigit().foregroundStyle(Palette.text)
                }
            }
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: Space.s2) {
                    Text("+\(finished.xp) XP").type(.t28).monospacedDigit().foregroundStyle(Palette.accent).lineLimit(1)
                    if finished.leveledUp { Badge(text: "Level up") }
                }
                Text("\(level.required - level.current) XP to Level \(level.level + 1)").type(.t14).foregroundStyle(Palette.muted)
                Bar(value: fraction).padding(.top, Space.s2).accessibilityLabel("Level \(level.level + 1) progress")
            }
        }
        .pad()
        .frame(maxWidth: .infinity, alignment: .leading)
        .raised()
    }

    private func tile(_ label: String, _ value: String, _ unit: String) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text(label).type(.t14).foregroundStyle(Palette.muted)
            HStack(alignment: .firstTextBaseline, spacing: Space.s1) {
                Text(value).type(.t20).monospacedDigit().foregroundStyle(Palette.text)
                Text(unit).type(.t14).foregroundStyle(Palette.muted)
            }
            .lineLimit(1).minimumScaleFactor(0.7)
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .raised()
    }
}
