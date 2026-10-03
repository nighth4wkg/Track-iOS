import Foundation
import TrackCore

/// For the screenshot run on GitHub's Mac (.github/workflows/screens.yml, tools/screens.sh): `-screen <name>` opens
/// that screen over the demo data, so every screen can be checked in the iOS Simulator without an iPhone. Without
/// the argument nothing here runs.
enum ScreenshotMode {
    static let screen: String? = {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-screen"), index + 1 < arguments.count else { return nil }
        return arguments[index + 1]
    }()

    static func apply(_ model: AppModel) {
        // The UI tests (UITests/) hand over their own training to start from.
        if let json = ProcessInfo.processInfo.environment["TRACK_SEED"], let seed = try? TrainingFile.decode(Data(json.utf8)) {
            model.restore(seed)
        }
        guard let screen else { return }
        let latest = model.training.sessions.first
        switch screen {
        case "history": model.tab = .history
        case "progress": model.tab = .progress
        case "rank": model.tab = .rank
        case "detail": model.tab = .history; model.history = latest
        case "recap": if let latest { model.finished = Finished(id: latest.id, xp: 45, level: 5, leveledUp: false, rankUps: ["Chest → Strong"]) }
        case "confirm": if let split = model.training.splits.first { model.deleteSplit(split) }
        case "name": model.naming = Naming(title: "Create a split", action: "Create split") { _ in }
        case "workout":
            guard let split = model.training.splits.first else { return }
            model.start(split)
            // Mid-workout: the first exercise done (it folds), the next one started, the rest timer running.
            model.update { training in
                guard var active = training.active, active.exercises.count > 1 else { return }
                for index in active.exercises[0].sets.indices { active.exercises[0].sets[index].done = true }
                active.exercises[1].sets[0].done = true
                training.active = active
                training.restUntil = nowMillis() + 75_000
            }
        default: break
        }
    }
}
