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

    /// Views' test hooks (perfHook): [key, value].
    static let hook = Notification.Name("perf.hook")

    /// -perfWork, only with -dryRun (nothing saved, no rest alerts; the data and the Progress choices are put back at
    /// the end): every animation in turn. Settings, a split's page (and its edit mode), a toast, a dialog; History's
    /// dates, months, a workout's sheet and its cards; Progress's periods and measures; Rank's rows; then the workout
    /// (the one going, else one from the first split, in memory): its cards, set ticks (rest starts), the set keyboard,
    /// arranging, the picker with its muscle filter switched quickly (twice, faster the second time), a search typed
    /// and two exercises added, and leaving and coming back.
    private static func work(_ model: AppModel) async {
        try? await Task.sleep(for: .seconds(4))
        let going = model.training.active
        guard let split = going.map({ Split(id: $0.splitId, name: $0.name, exercises: $0.exercises) }) ?? model.training.splits.first else { return }
        let before = model.training
        let defaults = UserDefaults.standard, kept = ["track.volumePeriod", "track.measure"].map { ($0, defaults.object(forKey: $0)) }
        let poke = { (key: String, value: String) in NotificationCenter.default.post(name: hook, object: [key, value]) }
        let exercises = { model.training.active?.exercises ?? [] }
        var steps: [(String, Double, () -> Void)] = []
        steps += [("settings open", 2, { poke("settings", "1") }), ("settings close", 2, { poke("settings", "") })]
        if let home = model.training.splits.first {
            steps += [("split page open", 2, { poke("home.split", home.id) }), ("split edit on", 1.5, { poke("split.edit", "") }),
                      ("split edit off", 1.5, { poke("split.edit", "") }), ("split page back", 2, { poke("home.split", "") })]
        }
        steps += [("toast", 3.5, { model.show("Test note") }),
                  ("dialog open", 1.5, { model.confirm = Confirm(title: "Test", message: "Nothing happens.", label: "OK") {} }),
                  ("dialog close", 1.5, { model.confirm = nil })]
        steps += [("tab history", 2, { model.tab = .history }), ("dates open", 1.5, { poke("history.dates", "1") }),
                  ("dates close", 1.5, { poke("history.dates", "") })]
        steps += ["-1", "-1", "1", "1"].map { step in ("month \(step)", 1, { poke("history.month", step) }) }
        if let latest = model.training.sessions.first {
            let ids = latest.exercises.prefix(2).map(\.id)
            steps.append(("history sheet open", 2, { model.history = latest }))
            steps += ids.flatMap { id in [("detail card open", 1.2, { poke("detail.card", id) }), ("detail card close", 1.2, { poke("detail.card", "") })] }
            steps.append(("history sheet close", 2, { model.history = nil }))
        }
        steps.append(("tab progress", 2, { model.tab = .progress }))
        steps += (Period.allCases + [Period.week]).map { period in ("period \(period.rawValue)", 1, { defaults.set(period.rawValue, forKey: "track.volumePeriod") }) }
        steps += (Tally.allCases + [Tally.volume]).map { tally in ("measure \(tally.rawValue)", 1, { defaults.set(tally.rawValue, forKey: "track.measure") }) }
        steps.append(("tab rank", 2, { model.tab = .rank }))
        steps += ["Chest", "Back"].flatMap { muscle in [("rank row open", 1.2, { poke("rank.row", muscle) }), ("rank row close", 1.2, { poke("rank.row", muscle) })] }
        steps.append(("tab home", 2, { model.tab = .home }))

        steps.append(("open workout", 2.5, { if going == nil { model.start(split) } else { model.workoutOpen = true } }))
        steps += [("open second card", 1.5, { poke("work.card", exercises().dropFirst().first?.id ?? "") }),
                  ("open first card", 1.5, { poke("work.card", exercises().first?.id ?? "") })]
        steps += (0..<(split.exercises.first?.sets.count ?? 0)).map { index in
            ("tick set \(index + 1)", 1.2, { if let first = exercises().first, first.sets.indices.contains(index) { model.toggle(set: first.sets[index].id, in: first.id) } })
        }
        steps += [("keyboard up", 1.5, { poke("work.focus", exercises().first?.sets.last.map { "\($0.id).kg" } ?? "") }),
                  ("keyboard down", 1.5, { poke("work.focus", "") }),
                  ("arrange on", 1.5, { poke("work.arrange", "1") }), ("arrange off", 1.5, { poke("work.arrange", "") })]
        steps.append(("open picker", 2.5, { poke("work.picker", "1") }))
        for pause in [0.4, 0.2] {
            steps += (LiftTable.groups + ["All"]).map { group in ("filter \(group)", pause, { poke("pick.group", group) }) }
        }
        steps += ["b", "be", "ben", "benc", "bench", ""].map { text in ("type '\(text)'", 0.15, { poke("pick.query", text) }) }
        let fresh = Catalog.names.filter { name in !split.exercises.contains { $0.name == name } }.prefix(2)
        steps += fresh.map { name in ("add exercise", 1.2, { poke("pick.add", name) }) }
        steps += [("close picker", 2.5, { poke("work.picker", "") }), ("leave workout", 2.5, { model.workoutOpen = false }),
                  ("back into workout", 2.5, { model.workoutOpen = true }), ("leave workout again", 2.5, { model.workoutOpen = false })]
        for (name, pause, step) in steps {
            FrameLog.mark(name)
            step()
            try? await Task.sleep(for: .seconds(pause))
        }
        FrameLog.mark(nil)
        for (key, value) in kept { defaults.set(value, forKey: key) }
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
