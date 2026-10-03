import XCTest
@testable import TrackCore

/// The workout rules, as the website applies them (tests/training-*.test.ts).
final class WorkoutTests: XCTestCase {
    private func split() -> Split {
        Split(id: "upper", name: "Upper", exercises: [
            Exercise(id: "bench", name: "Bench Press", sets: [TrainingSet(), TrainingSet()]),
            Exercise(id: "row", name: "Barbell row", sets: [TrainingSet()]),
        ])
    }

    func testStartCarriesLastTimesNumbersAsUnloggedSuggestions() throws {
        var training = Training()
        training.splits = [split()]
        try training.start(split(), now: 1000)
        training.updateActive(exercise: "bench") { $0.sets[0] = TrainingSet(id: $0.sets[0].id, kg: 60, reps: 8, rir: 2, done: true) }
        try training.finish(now: 2000)
        try training.start(split(), now: 3000)
        let bench = try XCTUnwrap(training.active?.exercises.first)
        XCTAssertEqual(bench.sets[0].kg, 60)
        XCTAssertEqual(bench.sets[0].reps, 8)
        XCTAssertFalse(bench.sets[0].done, "a suggestion until marked done")
        XCTAssertNil(bench.sets[1].kg, "nothing was logged for the second set")
    }

    func testFinishKeepsOnlyLoggedSetsAndNeedsOne() throws {
        var training = Training()
        try training.start(split(), now: 1000)
        XCTAssertThrowsError(try training.finish(now: 2000)) { XCTAssertEqual($0 as? TrainingError, .nothingLogged) }
        training.updateActive(exercise: "bench") { $0.sets[1] = try! $0.sets[1].edited(weight: "50", reps: "10", rir: "2", unit: .kg, autoLog: true) }
        try training.finish(now: 61_000)
        XCTAssertNil(training.active)
        XCTAssertEqual(training.sessions.count, 1)
        XCTAssertEqual(training.sessions[0].exercises.map(\.name), ["Bench Press"], "the row had nothing logged")
        XCTAssertEqual(training.sessions[0].exercises[0].sets.count, 1)
        XCTAssertEqual(training.sessions[0].exercises[0].sets[0].rir, 2)
        XCTAssertEqual(training.sessions[0].minutes, 1)
    }

    func testOnlyOneActiveWorkoutAndNotAnEmptySplit() throws {
        var training = Training()
        try training.start(split())
        XCTAssertThrowsError(try training.start(split())) { XCTAssertEqual($0 as? TrainingError, .activeWorkout) }
        training.discard()
        XCTAssertThrowsError(try training.start(Split(name: "Empty"))) { XCTAssertEqual($0 as? TrainingError, .noExercises) }
    }

    func testEditingFollowsTheWebsitesInputRules() {
        let set = TrainingSet()
        XCTAssertFalse(set.edited(weight: "60", reps: "8", rir: "", unit: .kg).done, "manual mode: typing doesn't log")
        XCTAssertTrue(set.edited(weight: "60", reps: "8", rir: "2", unit: .kg, autoLog: true).done)
        XCTAssertFalse(set.edited(weight: "60", reps: "8", rir: "", unit: .kg, autoLog: true).done, "auto mode waits for RIR")
        let logged = TrainingSet(kg: 60, reps: 8, rir: 2, done: true).edited(weight: "60", reps: "8", rir: "", unit: .kg, autoLog: true)
        XCTAssertEqual([logged.rir, logged.done ? 1 : 0], [0, 1], "a logged set cleared of RIR stays logged at 0")
        let lunge = Exercise(name: "Lunge", sets: [TrainingSet(kg: 40, reps: 10, rir: 1, done: true, side: .left)])
        XCTAssertEqual([lunge.nextSet.kg, Double(lunge.nextSet.reps ?? 0)], [40, 10], "a new set starts from the last")
        XCTAssertNil(lunge.nextSet.rir, "RIR is left to fill in")
        XCTAssertEqual(lunge.nextSet.side, .right)
        XCTAssertFalse(lunge.nextSet.done)
        XCTAssertNil(set.edited(weight: "6O", reps: "8", rir: "2", unit: .kg).kg, "not a number")
        XCTAssertNil(set.edited(weight: "60", reps: "-8", rir: "2", unit: .kg).reps)
        XCTAssertEqual(set.edited(weight: "60", reps: " 8 ", rir: "2", unit: .kg).reps, 8)
        XCTAssertEqual(set.edited(weight: "132.28", reps: "5", rir: "1", unit: .lb).kg!, 60, accuracy: 0.01)
        XCTAssertEqual(TrainingSet.display(kg: 60, unit: .lb), "132.28")
        XCTAssertEqual(TrainingSet.display(kg: 62.5, unit: .kg), "62.5")
        XCTAssertEqual(TrainingSet.display(kg: 60, unit: .kg), "60")
        XCTAssertThrowsError(try TrainingSet().toggledDone())
        XCTAssertEqual(try TrainingSet(kg: 40, reps: 5).toggledDone().rir, 0)
    }

    func testSidesAlternateAndOneSidedNamesStartInSides() {
        XCTAssertEqual(Exercise.new(named: "Single-arm dumbbell row").sets[0].side, .left)
        XCTAssertNil(Exercise.new(named: "Bench Press").sets[0].side)
        var exercise = Exercise(name: "Lunge", sets: [TrainingSet(), TrainingSet(), TrainingSet()])
        exercise = exercise.togglingSides()
        XCTAssertEqual(exercise.sets.map(\.side), [.left, .right, .left])
        XCTAssertEqual(exercise.nextSide, .right)
        exercise = exercise.togglingSides()
        XCTAssertEqual(exercise.sets.map(\.side), [.right, .left, .right])
        exercise = exercise.togglingSides()
        XCTAssertEqual(exercise.sets.map(\.side), [nil, nil, nil])
        XCTAssertNil(exercise.nextSide)
    }

    func testTheSplitFollowsTheWorkoutsShapeNotItsNumbers() throws {
        var training = Training()
        training.splits = [split()]
        try training.start(split())
        training.updateActive(exercise: "row") { $0.sets.append(TrainingSet(kg: 40, reps: 10, rir: 1, done: true)) }
        training.syncRoutine()
        XCTAssertEqual(training.splits[0].exercises[1].sets.count, 2)
        XCTAssertNil(training.splits[0].exercises[1].sets[1].kg)
    }

    func testTemplatesGiveThreeEmptySetsPerExercise() {
        let push = SplitTemplate.all[0].makeSplit()
        XCTAssertEqual(push.name, "Push")
        XCTAssertEqual(push.exercises.count, 5)
        XCTAssertTrue(push.exercises.allSatisfy { $0.sets.count == 3 && $0.sets.allSatisfy { !$0.done && $0.kg == nil } })
    }

    func testMovingItems() {
        XCTAssertEqual([1, 2, 3].moved(0, to: 2), [2, 3, 1])
        XCTAssertEqual([1, 2, 3].moved(2, to: 0), [3, 1, 2])
        XCTAssertEqual([1, 2, 3].moved(2, to: 3), [1, 2, 3], "past the end stays put")
    }
}
