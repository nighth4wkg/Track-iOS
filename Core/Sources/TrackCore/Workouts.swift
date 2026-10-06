import Foundation

// Starting, editing and finishing workouts (lib/training-sessions.ts, split-templates.ts).

extension Training {
    /// The split's most recent finished workout.
    public func latestSession(of splitId: String) -> Session? {
        sessions.filter { $0.splitId == splitId && $0.finishedAt != nil }
            .max { a, b in a.finishedAt! == b.finishedAt! ? a.id < b.id : a.finishedAt! < b.finishedAt! }
    }

    /// Starts the split. Each set carries over last time's numbers (matched by exercise, else by name in order) as
    /// suggestions, not logged until marked done. The side comes from the split, so turning sides off there sticks.
    public mutating func start(_ split: Split, now: Int = nowMillis(), carryOver: Bool = true) throws {
        if active != nil { throw TrainingError.activeWorkout }
        if split.exercises.isEmpty { throw TrainingError.noExercises }
        let previous = latestSession(of: split.id)
        var byName: [String: [Exercise]] = [:]
        for exercise in previous?.exercises ?? [] { byName[exercise.name, default: []].append(exercise) }
        var occurrences: [String: Int] = [:]
        let exercises = split.exercises.map { exercise -> Exercise in
            let occurrence = occurrences[exercise.name, default: 0]
            occurrences[exercise.name] = occurrence + 1
            let last = previous?.exercises.first { $0.id == exercise.id }
                ?? byName[exercise.name].flatMap { $0.indices.contains(occurrence) ? $0[occurrence] : nil }
            var started = exercise
            started.sets = exercise.sets.enumerated().map { index, routineSet in
                let candidate = carryOver ? last.flatMap { $0.sets.indices.contains(index) ? $0.sets[index] : nil } : routineSet
                let saved = candidate.flatMap { $0.isValid ? $0 : nil }
                return TrainingSet(kg: saved?.kg, reps: saved?.reps, rir: saved?.rir, side: routineSet.side)
            }
            return started
        }
        active = Session(name: split.name, exercises: exercises, splitId: split.id, startedAt: now)
        restUntil = nil
    }

    /// Saves the active workout to the history: only sets marked done, and only exercises with any. The split takes
    /// the workout's shape now, not while it runs, so a discarded workout leaves the split as it was.
    public mutating func finish(now: Int = nowMillis()) throws {
        guard var session = active else { throw TrainingError.noActiveWorkout }
        if now < session.startedAt { throw TrainingError.finishBeforeStart }
        if session.completedSets.isEmpty { throw TrainingError.nothingLogged }
        syncRoutine()
        session.finishedAt = now
        session.exercises = session.exercises.compactMap { exercise in
            var kept = exercise
            kept.sets = exercise.sets.filter { $0.done && $0.isValid }
            return kept.sets.isEmpty ? nil : kept
        }
        sessions.insert(session, at: 0)
        active = nil
        restUntil = nil
    }

    /// Drops the active workout without saving it.
    public mutating func discard() {
        active = nil
        restUntil = nil
    }

    /// Changes one exercise of the active workout.
    public mutating func updateActive(exercise id: String, _ change: (inout Exercise) -> Void) {
        guard let index = active?.exercises.firstIndex(where: { $0.id == id }) else { return }
        change(&active!.exercises[index])
    }

    /// Gives the split the active workout's shape (its name, exercises, set counts and sides), so the next start
    /// begins from it. Numbers are not copied into the split.
    public mutating func syncRoutine() {
        guard let active, let index = splits.firstIndex(where: { $0.id == active.splitId }) else { return }
        let routine = splits[index]
        let same = routine.name == active.name && routine.exercises.count == active.exercises.count
            && zip(routine.exercises, active.exercises).allSatisfy { r, a in
                r.id == a.id && r.name == a.name && r.sets.count == a.sets.count
                    && zip(r.sets, a.sets).allSatisfy { $0.side == $1.side }
            }
        if same { return }
        splits[index].name = active.name
        splits[index].exercises = active.exercises.map { exercise in
            var shape = exercise
            shape.sets = exercise.sets.map { TrainingSet(side: $0.side) }
            return shape
        }
    }
}

// MARK: Starter splits

public struct SplitTemplate: Sendable, Identifiable {
    public let name: String
    public let exercises: [String]
    public var id: String { name }

    /// One tap gives a new user a split they can start straight away. Names match the exercise library.
    public static let all = [
        SplitTemplate(name: "Push", exercises: ["Bench Press", "Overhead Press", "Incline dumbbell press", "Dumbbell lateral raise", "Triceps pushdown"]),
        SplitTemplate(name: "Pull", exercises: ["Pull-up", "Barbell row", "Lat pulldown", "Face pull", "Dumbbell curl"]),
        SplitTemplate(name: "Legs", exercises: ["Back squat", "Romanian deadlift", "Leg press", "Lying leg curl", "Standing calf raise"]),
        SplitTemplate(name: "Full body", exercises: ["Back squat", "Bench Press", "Barbell row", "Overhead Press", "Romanian deadlift"]),
    ]

    /// A new split from the template: each exercise starts with three empty sets.
    public func makeSplit() -> Split {
        Split(name: name, exercises: exercises.map { name in
            var exercise = Exercise.new(named: name)
            exercise.sets += (1..<3).map { _ in TrainingSet() }
            return exercise
        })
    }
}
