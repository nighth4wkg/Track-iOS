import Foundation
import TrackCore

/// The workout's actions that ask first or can be undone, as on the website (hooks/use-workout-actions.ts).
extension AppModel {
    func startRest() { update { $0.restUntil = nowMillis() + $0.settings.restSeconds * 1000 } }

    /// Ends the rest: Skip, in Track and on the Live Activity. With none to end (the Live Activity still showing one
    /// that ran out), it only puts the Live Activity right; there's nothing to save.
    func skipRest() {
        if training.restUntil != nil { update { $0.restUntil = nil } } else if training.active != nil { RestLive.idle() } else { RestLive.end() }
    }

    /// The rest's −15s and +15s, as the PWA's: from now if none is running; one pushed into the past ends.
    func shiftRest(by seconds: Int) {
        update { training in
            let until = (training.restUntil ?? nowMillis()) + seconds * 1000
            training.restUntil = until > nowMillis() ? until : nil
        }
    }

    /// Removes a set as counted (both sides of a pair); an exercise's only set takes the exercise with it. One Undo
    /// brings it back.
    func removeSet(_ setId: String, in exerciseId: String) {
        guard let active = training.active, let exercise = active.exercises.first(where: { $0.id == exerciseId }),
              let group = exercise.setGroups.first(where: { $0.contains { $0.id == setId } }),
              let index = exercise.sets.firstIndex(where: { $0.id == group[0].id }) else { return }
        if exercise.setCount == 1 { removeExercise(exercise); return }
        let sessionId = active.id, ids = Set(group.map(\.id))
        update { $0.updateActive(exercise: exerciseId) { $0.sets.removeAll { ids.contains($0.id) } } }
        show("Set removed.") { [weak self] in
            self?.update { training in
                guard training.active?.id == sessionId else { return }
                training.updateActive(exercise: exerciseId) { exercise in
                    guard !exercise.sets.contains(where: { ids.contains($0.id) }) else { return }
                    exercise.sets.insert(contentsOf: group, at: min(index, exercise.sets.count))
                }
            }
        }
    }

    /// Removes an exercise from the workout at once, with Undo (its split keeps it).
    func removeExercise(_ exercise: Exercise) {
        guard let active = training.active, let index = active.exercises.firstIndex(where: { $0.id == exercise.id }) else { return }
        let sessionId = active.id
        update { $0.active?.exercises.remove(at: index) }
        show("Exercise removed.") { [weak self] in
            self?.update { training in
                guard var active = training.active, active.id == sessionId, !active.exercises.contains(where: { $0.id == exercise.id }) else { return }
                active.exercises.insert(exercise, at: min(index, active.exercises.count))
                training.active = active
            }
        }
    }

    /// Swaps an exercise for another, same place and sets, in the workout (`inWorkout`) or the split, and in the split it
    /// belongs to as well. When that split has it, this asks first; from a workout the split changes now, so discarding
    /// the workout doesn't undo the swap (as on the website).
    func swap(_ exercise: Exercise, for name: String, inWorkout: Bool, splitId: String?) {
        let change: () -> Void = { [weak self] in
            self?.update { training in
                if inWorkout { training.updateActive(exercise: exercise.id) { $0.name = name } }
                guard let splitId else { return }
                training.edit(splitId) { split in
                    if let at = split.exercises.firstIndex(where: { $0.id == exercise.id }) { split.exercises[at].name = name }
                }
            }
        }
        guard let split = training.splits.first(where: { $0.id == splitId }), split.exercises.contains(where: { $0.id == exercise.id })
        else { change(); return }
        confirm = Confirm(title: "Use \(name) instead?",
                          message: inWorkout ? "It replaces \(exercise.name) here and in \(split.name), even if you discard this workout."
                                             : "It replaces \(exercise.name) in \(split.name). Past workouts stay as they are.",
                          label: "Swap", action: change)
    }

    /// The owner's rule, as the PWA's: a workout saves only when every set is done (the header's count is full).
    func finish() {
        guard let active = training.active else { return }
        guard active.exercises.doneCount >= active.exercises.plannedCount else { problem("Mark all exercises done first."); return }
        save()
    }

    func save() {
        let before = Experience.progress(of: training.sessions)
        let bodyweight = training.settings.bodyweight
        let choices = training.settings.lifts ?? [:]
        let ranksBefore = bodyweight.map { training.sessions.muscleRanks(bodyweight: $0, choices: choices) } ?? []
        update { try $0.finish(); $0.awardLatestQuests() }
        guard training.active == nil, let session = training.sessions.first, session.finishedAt != nil else { return }
        let after = Experience.progress(of: training.sessions)
        let ranksAfter = bodyweight.map { training.sessions.muscleRanks(bodyweight: $0, choices: choices) } ?? []
        workoutOpen = false
        go(.progress)
        finished = Finished(id: session.id, xp: after.total - before.total, level: after.level, leveledUp: after.level > before.level,
                            rankUps: zip(ranksBefore, ranksAfter).filter { $1.best != nil && $1.rank > $0.rank }.map { "\($1.muscle.rawValue) → \($1.name)" })
    }

    func discard() {
        confirm = Confirm(title: "Discard this workout?", message: "Its sets won’t be saved. Your split stays.", label: "Discard workout", destructive: true) { [weak self] in
            guard let self, let kept = training.active else { return }
            update { $0.discard() }
            workoutOpen = false
            show("Workout discarded.") { [weak self] in
                guard let self, training.active == nil else { return }
                update { $0.active = kept }
            }
        }
    }

    /// A split name already used by another split (`except`: the one being renamed), as the naming dialog's problem.
    func splitNameTaken(_ name: String, except id: String? = nil) -> String? {
        training.splits.contains { $0.id != id && $0.name.caseInsensitiveCompare(name) == .orderedSame } ? "You already have a split called \(name)." : nil
    }

    func deleteSplit(_ split: Split) {
        confirm = Confirm(title: "Delete \(split.name)?", message: "Its past workouts stay in History.", label: "Delete split",
                          destructive: true) { [weak self] in
            guard let self, let index = training.splits.firstIndex(where: { $0.id == split.id }) else { return }
            pages.removeAll { $0 == .split(split.id) }
            update { $0.splits.remove(at: index) }
            show("Split deleted.") { [weak self] in
                guard let self, !training.splits.contains(where: { $0.id == split.id }) else { return }
                update { $0.splits.insert(split, at: min(index, $0.splits.count)) }
            }
        }
    }

    func deleteWorkout(_ session: Session) {
        confirm = Confirm(title: "Delete this workout?", message: "Its sets and XP go too. You can undo.",
                          label: "Delete workout", destructive: true) { [weak self] in
            guard let self, let index = training.sessions.firstIndex(where: { $0.id == session.id }) else { return }
            pages.removeAll { $0 == .session(session.id) }
            update { $0.sessions.remove(at: index) }
            show("Workout deleted.") { [weak self] in self?.update { $0.sessions.insert(session, at: min(index, $0.sessions.count)) } }
        }
    }
}

extension Training {
    /// Like updateActive, for a change that can fail (marking a set done without numbers).
    mutating func updateActiveThrowing(exercise id: String, _ change: (inout Exercise) throws -> Void) throws {
        guard let index = active?.exercises.firstIndex(where: { $0.id == id }) else { return }
        try change(&active!.exercises[index])
    }
}
