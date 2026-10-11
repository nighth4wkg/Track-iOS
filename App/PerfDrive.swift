import Foundation
import TrackCore

/// For profiling (.github/workflows/profile.yml): launched with -frameLog -perfActions, Track does a round of everyday
/// actions by itself, a few seconds apart and with nothing touching it, and FrameLog logs what each one cost: open
/// the workout, tick the first exercise's sets (the last folds its card), untick one (it opens), leave, each tab, a
/// finished workout's sheet open and closed, back into the workout, leave. Without the argument nothing here runs.
@MainActor enum PerfDrive {
    static func run(_ model: AppModel) async {
        guard ProcessInfo.processInfo.arguments.contains("-perfActions") else { return }
        try? await Task.sleep(for: .seconds(4))
        guard let split = model.training.splits.first else { return }
        let first = { model.training.active?.exercises.first }
        let tick = { (index: Int) in if let exercise = first(), exercise.sets.indices.contains(index) { model.toggle(set: exercise.sets[index].id, in: exercise.id) } }
        let sets = split.exercises.first?.sets.count ?? 0
        var steps: [(String, () -> Void)] = [("open workout", { model.start(split) })]
        steps += (0..<max(sets - 1, 0)).map { index in ("tick set \(index + 1)", { tick(index) }) }
        steps += [("tick last set, card folds", { tick(sets - 1) }), ("untick it, card opens", { tick(sets - 1) }),
                  ("leave workout", { model.workoutOpen = false })]
        steps += AppTab.allCases.dropFirst().map { tab in ("tab \(tab)", { model.tab = tab }) } + [("tab home", { model.tab = .home })]
        steps += [("history sheet open", { model.history = model.training.sessions.first }), ("history sheet close", { model.history = nil }),
                  ("back into workout", { model.workoutOpen = true }), ("leave workout again", { model.workoutOpen = false })]
        for (name, step) in steps {
            FrameLog.mark(name)
            step()
            try? await Task.sleep(for: .seconds(3.5))
        }
        FrameLog.mark(nil)
    }
}
