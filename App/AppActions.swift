import Foundation
import TrackCore

/// The workout's actions that ask first or can be undone, as on the website (hooks/use-workout-actions.ts).
extension AppModel {
    func startRest() { update { $0.restUntil = nowMillis() + $0.settings.restSeconds * 1000 } }

    /// Removes a set; its exercise goes too when it was the last one. One Undo brings both back.
    func removeSet(_ setId: String, in exerciseId: String) {
        guard let active = training.active, let at = active.exercises.firstIndex(where: { $0.id == exerciseId }),
              let index = active.exercises[at].sets.firstIndex(where: { $0.id == setId }) else { return }
        let exercise = active.exercises[at], set = exercise.sets[index], sessionId = active.id
        let last = exercise.sets.count == 1
        update { training in
            if last { training.active?.exercises.remove(at: at) } else { training.updateActive(exercise: exerciseId) { $0.sets.remove(at: index) } }
        }
        show(last ? "\(exercise.name) removed" : "Set removed") { [weak self] in
            self?.update { training in
                guard training.active?.id == sessionId else { return }
                if last, !(training.active?.exercises.contains { $0.id == exercise.id } ?? true) {
                    training.active?.exercises.insert(exercise, at: min(at, training.active?.exercises.count ?? 0))
                } else {
                    training.updateActive(exercise: exerciseId) { $0.sets.insert(set, at: min(index, $0.sets.count)) }
                }
            }
        }
    }

    func removeExercise(_ exercise: Exercise) {
        confirm = Confirm(title: "Remove \(exercise.name)?",
                          message: "Remove this exercise and its entered sets from the current workout. Your saved split and past workouts stay unchanged.",
                          label: "Remove exercise", destructive: true) { [weak self] in
            self?.update { $0.active?.exercises.removeAll { $0.id == exercise.id } }
        }
    }

    /// Asks first, as the website does: what will be saved, and that unmarked sets are left out.
    func finish() {
        guard let active = training.active else { return }
        let done = active.completedSets.count
        guard done > 0 else { message = "Tap the circle beside each set you’ve done, then finish."; return }
        confirm = Confirm(title: "Finish this workout?",
                          message: "Save \(count(done, "done set")). Sets not marked done are left out.",
                          label: "Finish workout") { [weak self] in self?.save() }
    }

    func save() {
        let before = Experience.progress(of: training.sessions)
        let bodyweight = training.settings.bodyweight
        let ranksBefore = bodyweight.map { training.sessions.muscleRanks(bodyweight: $0) } ?? []
        update { try $0.finish(); $0.awardLatestQuests() }
        guard training.active == nil, let session = training.sessions.first, session.finishedAt != nil else { return }
        let after = Experience.progress(of: training.sessions)
        let ranksAfter = bodyweight.map { training.sessions.muscleRanks(bodyweight: $0) } ?? []
        workoutOpen = false
        arrangingExercises = false
        tab = .progress
        xpFill = (before.total, after.total)
        finished = Finished(id: session.id, xp: after.total - before.total, level: after.level, leveledUp: after.level > before.level,
                            rankUps: zip(ranksBefore, ranksAfter).filter { $1.best != nil && $1.rank > $0.rank }.map { "\($1.muscle.rawValue) → \($1.name)" })
    }

    func discard() {
        confirm = Confirm(title: "Discard this workout?", message: "Its sets won’t be saved.", label: "Discard workout", destructive: true) { [weak self] in
            self?.update { $0.discard() }
            self?.workoutOpen = false
            self?.arrangingExercises = false
        }
    }

    func deleteSplit(_ split: Split) {
        confirm = Confirm(title: "Delete \(split.name)?", message: "Your finished workouts stay in History.", label: "Delete split",
                          destructive: true) { [weak self] in self?.update { $0.splits.removeAll { $0.id == split.id } } }
    }

    func deleteWorkout(_ session: Session) {
        confirm = Confirm(title: "Delete this workout?", message: "\(session.name) and its sets are removed from History, with its XP.",
                          label: "Delete workout", destructive: true) { [weak self] in
            self?.history = nil
            self?.update { $0.sessions.removeAll { $0.id == session.id } }
        }
    }
}
