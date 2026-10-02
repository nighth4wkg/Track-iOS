import Foundation
import Observation
import TrackCore

/// Where the person keeps their training: synced through their Track account, or only on this iPhone. Chosen once on
/// the first screen; local can turn on sync later in Settings.
enum StorageMode: String {
    case sync, local
}

/// What a finished workout earned, for the summary and its celebration.
struct FinishSummary: Identifiable {
    let id = UUID()
    let name: String
    let sets: Int
    let volume: Double
    let minutes: Int
    let xp: Int
    let level: Int
    let leveledUp: Bool
    /// Exercises whose heaviest weight went up.
    let records: [String]
    /// Muscles that reached a new rank, as "Chest → Strong".
    let rankUps: [String]
    /// Achievements this workout earned.
    let achievements: [String]
}

/// The app's state: the training data (saved to this device after every change), the storage choice, and what's
/// on screen.
@Observable
final class AppModel {
    private(set) var training: Training
    /// nil until the first screen's choice is made.
    private(set) var mode: StorageMode?
    /// Why the saved copy couldn't be read, if it couldn't. The app then starts empty without overwriting it.
    private(set) var loadError: String?
    /// A problem to show (an alert), such as finishing without a logged set.
    var message: String?
    var workoutOpen = false
    var summary: FinishSummary?

    private let file: TrainingFile?
    @ObservationIgnored private var canSave = true
    private static let modeKey = "track.storageMode"

    init(file: TrainingFile? = try? TrainingFile.standard()) {
        self.file = file
        mode = UserDefaults.standard.string(forKey: Self.modeKey).flatMap(StorageMode.init)
        do {
            training = try file?.load() ?? Training()
        } catch {
            training = Training()
            canSave = false
            loadError = "Your saved workouts couldn’t be read, so they were left untouched."
        }
    }

    func choose(_ choice: StorageMode) {
        mode = choice
        UserDefaults.standard.set(choice.rawValue, forKey: Self.modeKey)
    }

    /// Changes the training data, keeps the split in step with the workout, and saves it on this device. A change
    /// that throws is shown and not applied.
    func update(_ change: (inout Training) throws -> Void) {
        var next = training
        do { try change(&next) } catch { message = error.localizedDescription; return }
        next.syncRoutine()
        next.editedAt = nowMillis()
        if next.restUntil != training.restUntil {
            if let until = next.restUntil, until > nowMillis() {
                RestAlert.schedule(at: until)
                RestLive.show(until: until, seconds: max(1, (until - nowMillis()) / 1000), workout: next.active?.name ?? "Track")
            } else {
                RestAlert.cancel()
                RestLive.end()
            }
        }
        training = next
        guard canSave, let file else { return }
        do { try file.save(next) } catch { message = "Couldn’t save on this iPhone. Free up some space and try again." }
    }

    /// Replaces everything with a backup (the website's backup file, or one exported here).
    func restore(_ backup: Training) {
        update { $0 = backup }
        workoutOpen = false
    }

    // MARK: Workouts

    func start(_ split: Split) {
        update { try $0.start(split) }
        if training.active != nil { workoutOpen = true }
    }

    /// Logs a set, or un-logs it. Logging starts the rest timer.
    func toggle(set setId: String, in exerciseId: String) {
        update { training in
            var started = false
            try training.updateActiveThrowing(exercise: exerciseId) { exercise in
                guard let index = exercise.sets.firstIndex(where: { $0.id == setId }) else { return }
                exercise.sets[index] = try exercise.sets[index].toggledDone()
                started = exercise.sets[index].done
            }
            if started { training.restUntil = nowMillis() + training.settings.restSeconds * 1000 }
        }
    }

    func finish() {
        let before = Experience.progress(of: training.sessions)
        let records = training.sessions.personalRecords
        let bodyweight = training.settings.bodyweight
        let ranksBefore = bodyweight.map { training.sessions.muscleRanks(bodyweight: $0) } ?? []
        update { try $0.finish(); $0.awardLatestQuests() }
        guard training.active == nil, let session = training.sessions.first, session.finishedAt != nil else { return }
        let after = Experience.progress(of: training.sessions)
        let newRecords = session.exercises.filter { exercise in
            let best = exercise.sets.compactMap(\.kg).max() ?? 0
            return records[exercise.name].map { best > $0 } ?? false
        }.map(\.name)
        let ranksAfter = bodyweight.map { training.sessions.muscleRanks(bodyweight: $0) } ?? []
        let rankUps = zip(ranksBefore, ranksAfter).filter { $1.best != nil && $1.rank > $0.rank }
            .map { "\($1.muscle.rawValue) → \($1.name)" }
        workoutOpen = false
        summary = FinishSummary(name: session.name, sets: session.completedSets.count, volume: session.volume,
                                minutes: session.minutes, xp: after.total - before.total, level: after.level,
                                leveledUp: after.level > before.level, records: newRecords, rankUps: rankUps,
                                achievements: (session.questAwards ?? []).compactMap { award in Quest.all.first { $0.id == award.questId }?.title })
    }

    func discard() {
        update { $0.discard() }
        workoutOpen = false
    }
}

extension Training {
    /// Like updateActive, for a change that can fail (marking a set done without numbers).
    mutating func updateActiveThrowing(exercise id: String, _ change: (inout Exercise) throws -> Void) throws {
        guard let index = active?.exercises.firstIndex(where: { $0.id == id }) else { return }
        try change(&active!.exercises[index])
    }
}
