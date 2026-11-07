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
            let level = model.derived("xp") { Experience.progress(of: $0) }
            let before = Dictionary(sessions.filter { $0.id != session.id }.personalRecords.map { ($0.name, $0.kg) }, uniquingKeysWith: max)
            let bests = session.exercises.compactMap { exercise -> (name: String, set: TrainingSet, fresh: Bool)? in
                guard let set = exercise.sets.filter(\.isValid).top else { return nil }
                return (exercise.name, set, before[exercise.name].map { (set.kg ?? 0) > $0 } ?? false)
            }
            DeepPage {
                // Its parts rise one after another (the PWA's .celebrate), then new bests and a level up pop.
                VStack(alignment: .leading, spacing: 0) {
                    Text("Workout complete").type(.t14).foregroundStyle(Palette.muted)
                    Text("Nice workout!").type(.t32).foregroundStyle(Palette.text).accessibilityAddTraits(.isHeader)
                    Text(session.name + dot + Date(timeIntervalSince1970: Double(at) / 1000).formatted(.gregorian.weekday(.wide).month(.abbreviated).day()))
                        .type(.t14).foregroundStyle(Palette.muted)
                }
                .rises(0)
                xpCard(level).padding(.top, Space.s4).rises(1)
                HStack(spacing: Space.s3) {
                    StatTile(label: "Duration", value: "\(session.minutes)", unit: "min")
                    StatTile(label: "Volume", value: weight(session.volume, unit), unit: unit.rawValue)
                    StatTile(label: "Streak", value: "\(sessions.weeklyStreak(at: at))", unit: "wk")
                }
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, Space.s3)
                .rises(2)
                if !bests.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Best sets").type(.t20).foregroundStyle(Palette.text).padding(.top, Space.s6).accessibilityAddTraits(.isHeader)
                        RowCard {
                            ForEach(bests, id: \.name) { best in
                                Row(title: best.name) {
                                    if best.fresh { Badge(text: "New best").popsOnShow(after: Self.badgeDelay) }
                                    Text(setText(best.set, unit))
                                        .type(.t14).monospacedDigit().foregroundStyle(Palette.text)
                                }
                            }
                        }
                        .padding(.top, Space.s2)
                    }
                    .rises(3)
                }
                // Room for the dock, so the last card scrolls clear of it.
                Color.clear.frame(height: Size.primary + floatingGap - homeIndicator)
            }
            .overlay(alignment: .bottom) {
                Button("Continue", action: leave).buttonStyle(PrimaryStyle())
                    .padding(.horizontal, Space.s4)
                    .frame(maxWidth: Size.column)
                    .floatingBottom()
                    .floatingBar(Size.primary)
                    .arrives(forward: true, shifts: false) // fades in with the recap, not at full strength alone
            }
            .sensoryFeedback(.success, trigger: finished.id)
        } else {
            DeepPage {
                Text("Workout saved.").type(.t16).foregroundStyle(Palette.text)
                Button("Continue", action: leave).buttonStyle(PrimaryStyle()).padding(.top, Space.s4)
            }
        }
    }

    /// The badges pop once their parts have risen (the PWA's --motion + --motion-fast).
    private static var badgeDelay: Double { Motion.normal + Motion.fast }

    /// Back to Home, done with the recap: Home comes back as a page does (owner: it cut straight to it).
    private func leave() { model.finished = nil; model.go(.home, swapping: false) }

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
                // The PWA's wrapping row: on a narrow phone "Level up" drops under the XP rather than cutting it short.
                let xp = Text("+\(finished.xp) XP").type(.t28).monospacedDigit().foregroundStyle(Palette.accent).fixedSize()
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: Space.s2) { xp; if finished.leveledUp { Badge(text: "Level up").popsOnShow(after: Self.badgeDelay) } }
                    VStack(alignment: .leading, spacing: Space.s1) { xp; if finished.leveledUp { Badge(text: "Level up").popsOnShow(after: Self.badgeDelay) } }
                }
                Text("\(level.required - level.current) XP to Level \(level.level + 1)").type(.t14).foregroundStyle(Palette.muted)
                Bar(value: fraction).padding(.top, Space.s2).accessibilityLabel("Level \(level.level + 1) progress")
            }
        }
        .pad()
        .frame(maxWidth: .infinity, alignment: .leading)
        .raised()
    }
}
