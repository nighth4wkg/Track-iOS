import Foundation
import TrackCore

/// For profiling (.github/workflows/profile.yml): launched with -frameLog -perfActions, Track does a round of everyday
/// actions by itself, a few seconds apart and with nothing touching it, and FrameLog logs what each one cost: open
/// the workout, tick the first exercise's sets (the last folds its card), untick one (it opens), leave, each tab, a
/// finished workout's sheet open and closed, back into the workout, leave. Without the argument nothing here runs.
@MainActor enum PerfDrive {
    static func run(_ model: AppModel) async {
        if ProcessInfo.processInfo.arguments.contains("-perfLook") { return await look(model) }
        if ProcessInfo.processInfo.arguments.contains("-perfWork"), AppModel.dryRun { return await work(model) }
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

    /// The workout's own test hooks: open or close the picker (object nil closes), open a card (its id).
    static let picker = Notification.Name("perf.picker"), card = Notification.Name("perf.card")
    /// The picker's: ["group", name], ["query", text] or ["pick", name].
    static let filter = Notification.Name("perf.filter")

    /// -perfWork, only with -dryRun (nothing saved; the data is put back at the end): a workout from the first split,
    /// a card opened and back, the first exercise's sets ticked (rest starts), the picker opened, its muscle filter
    /// switched quickly (twice, faster the second time), a search typed and cleared, two exercises added, the picker
    /// closed, the workout left, back, left.
    private static func work(_ model: AppModel) async {
        try? await Task.sleep(for: .seconds(4))
        guard model.training.active == nil, let split = model.training.splits.first else { return }
        let before = model.training
        let post = { (name: Notification.Name, object: Any?) in NotificationCenter.default.post(name: name, object: object) }
        let exercises = { model.training.active?.exercises ?? [] }
        var steps: [(String, Double, () -> Void)] = [("open workout", 2.5, { model.start(split) })]
        steps += [("open second card", 1.5, { post(card, exercises().dropFirst().first?.id) }), ("open first card", 1.5, { post(card, exercises().first?.id) })]
        steps += (0..<(split.exercises.first?.sets.count ?? 0)).map { index in
            ("tick set \(index + 1)", 1.2, { if let first = exercises().first, first.sets.indices.contains(index) { model.toggle(set: first.sets[index].id, in: first.id) } })
        }
        steps.append(("open picker", 2.5, { post(picker, true) }))
        for pause in [0.4, 0.2] {
            steps += (LiftTable.groups + ["All"]).map { group in ("filter \(group)", pause, { post(filter, ["group", group]) }) }
        }
        steps += ["b", "be", "ben", "benc", "bench", ""].map { text in ("type '\(text)'", 0.15, { post(filter, ["query", text]) }) }
        let fresh = Catalog.names.filter { name in !split.exercises.contains { $0.name == name } }.prefix(2)
        steps += fresh.map { name in ("add exercise", 1.2, { post(filter, ["pick", name]) }) }
        steps += [("close picker", 2.5, { post(picker, nil) }), ("leave workout", 2.5, { model.workoutOpen = false }),
                  ("back into workout", 2.5, { model.workoutOpen = true }), ("leave workout again", 2.5, { model.workoutOpen = false })]
        for (name, pause, step) in steps {
            FrameLog.mark(name)
            step()
            try? await Task.sleep(for: .seconds(pause))
        }
        FrameLog.mark(nil)
        model.dryRunEnd(before)
    }

    /// -perfLook: only looking around, nothing saved (safe on a phone with real data): each tab and back home, twice,
    /// then the latest workout's sheet opened and closed, twice.
    private static func look(_ model: AppModel) async {
        try? await Task.sleep(for: .seconds(4))
        var steps: [(String, () -> Void)] = []
        for _ in 0..<2 {
            steps += AppTab.allCases.dropFirst().map { tab in ("tab \(tab)", { model.tab = tab }) } + [("tab home", { model.tab = .home })]
        }
        if let latest = model.training.sessions.first {
            for _ in 0..<2 { steps += [("history sheet open", { model.history = latest }), ("history sheet close", { model.history = nil })] }
        }
        for (name, step) in steps {
            FrameLog.mark(name)
            step()
            try? await Task.sleep(for: .seconds(2.5))
        }
        FrameLog.mark(nil)
    }
}
