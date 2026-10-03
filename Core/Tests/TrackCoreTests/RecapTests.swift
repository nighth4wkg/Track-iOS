import XCTest
@testable import TrackCore

/// The recap and live records, with the website's own cases (tests/workout-recap.test.ts, tests/rewards.test.ts).
final class RecapTests: XCTestCase {
    private func session(_ id: String, _ split: String, _ finishedAt: Int, _ sets: [(Double, Int, Int)], name: String = "Bench press") -> Session {
        var session = Session(id: id, name: "Upper", exercises: [Exercise(id: "\(id)-e", name: name, sets: sets.enumerated().map { index, set in
            TrainingSet(id: "\(id)-\(index)", kg: set.0, reps: set.1, rir: set.2, done: true)
        })], splitId: split, startedAt: finishedAt - 30 * 60_000)
        session.finishedAt = finishedAt
        return session
    }

    func testRecapComparesThePriorMatchingSplit() throws {
        let previous = session("previous", "upper", 1_000, [(100, 5, 2)])
        let unrelated = session("lower", "lower", 1_500, [(50, 5, 2)])
        let current = session("current", "upper", 2_000_000, [(105, 5, 1), (100, 6, 1)])
        let recap = try XCTUnwrap([current, unrelated, previous].recap(of: "current"))
        XCTAssertEqual(recap.previous?.id, "previous")
        XCTAssertEqual(recap.volume, 1_125)
        XCTAssertEqual(recap.volumeDelta, 625)
        XCTAssertEqual(recap.sets, 2)
        XCTAssertEqual(recap.reps, 11)
        XCTAssertEqual(recap.minutes, 30)
        XCTAssertEqual(recap.best?.set.kg, 105)
        XCTAssertEqual(recap.records.count, 2)
        XCTAssertEqual(recap.observation, "Bench press added volume through 1 extra set.")
    }

    func testFirstResultAndMatchedVolume() {
        let first = session("first", "upper", 2_000_000, [(80, 8, 2)])
        XCTAssertNil([first].recap(of: "first")?.volumeDelta)
        XCTAssertEqual([first].recap(of: "first")?.observation, "First result saved. Next time, compare load, reps, and total work.")
        XCTAssertNil([first].recap(of: "missing"))
        let before = session("previous", "upper", 1_000, [(100, 5, 3)]), after = session("current", "upper", 2_000, [(100, 5, 1)])
        XCTAssertEqual([after, before].recap(of: "current")?.observation, "Same Bench press volume, with sets closer to failure.")
    }

    func testEveryHistoryRecordCelebratesLive() {
        let history = [session("s1", "push", 1, [(80, 6, 2), (80, 6, 2)], name: "Bench Press"),
                       session("s3", "push", 3, [(82.5, 6, 2), (70, 10, 2)], name: "Bench Press")]
        let bests = RecordBests(history)
        let today = [(85.0, 6), (70, 12), (90, 3), (60, 8), (80, 6)].map { TrainingSet(kg: $0.0, reps: $0.1, rir: 2, done: true) }
        let live = today.map { bests.record(for: "bench press ", $0) }
        XCTAssertEqual(live, [.heaviest(previousKg: 82.5), .repsForWeight(previousReps: 10), .heaviest(previousKg: 82.5), nil, nil])
    }

    func testBeatingOnBothCountsAndTodaysEarlierSets() {
        let bests = RecordBests([session("s1", "pull", 1, [(2, 2, 2), (1, 1, 2)], name: "Lat pulldown")])
        let set = { (kg: Double, reps: Int, done: Bool) in TrainingSet(kg: kg, reps: reps, rir: 2, done: done) }
        XCTAssertEqual(bests.record(for: "Lat pulldown", set(3, 3, true)), .heaviest(previousKg: 2))
        XCTAssertEqual(bests.record(for: "Lat pulldown", set(2, 3, true)), .repsForWeight(previousReps: 2))
        XCTAssertNil(bests.record(for: "Lat pulldown", set(2, 2, true)), "matching is not beating")
        let first = set(3, 2, true)
        XCTAssertNil(bests.record(for: "Lat pulldown", set(1, 2, true), earlierToday: [first]))
        XCTAssertEqual(bests.record(for: "Lat pulldown", set(4, 2, true), earlierToday: [first]), .heaviest(previousKg: 3))
        XCTAssertEqual(bests.record(for: "Lat pulldown", set(3, 2, true), earlierToday: [set(9, 9, false)]), .heaviest(previousKg: 2))
        let deeper = RecordBests([session("s1", "push", 1, [(100, 3, 2), (60, 8, 2)], name: "Bench Press")])
        XCTAssertEqual(deeper.record(for: "Bench Press", set(70, 9, true)), .repsAtOrAbove(previousReps: 3))
        XCTAssertNil(deeper.record(for: "Bench Press", set(70, 3, true)))
        XCTAssertNil(deeper.record(for: "Squat", set(100, 6, true)), "no history, no record")
        XCTAssertNil(deeper.record(for: "Bench Press", set(200, 6, false)), "not logged")
    }

    func testDurationsReadLikeTheWebsite() {
        XCTAssertEqual(trainingDuration(45), "45 min")
        XCTAssertEqual(trainingDuration(125), "2h 5m")
        XCTAssertEqual(trainingDuration(60), "1h")
        XCTAssertEqual(trainingDuration(28_884), "20d 1h")
    }

    func testFiltersMatchEveryWordAndTheDayRange() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Bangkok")!
        let day = { (d: Int) in millis(calendar.date(from: DateComponents(year: 2026, month: 9, day: d, hour: 12))!) }
        let sessions = [session("a", "u", day(1), [(60, 8, 2)]), session("b", "u", day(15), [(60, 8, 2)], name: "Back squat")]
        XCTAssertEqual(sessions.filtered(query: "bench", calendar: calendar).map(\.id), ["a"])
        XCTAssertEqual(sessions.filtered(query: "upper squat", calendar: calendar).map(\.id), ["b"])
        XCTAssertEqual(sessions.filtered(query: "", from: "2026-09-10", calendar: calendar).map(\.id), ["b"])
        XCTAssertEqual(sessions.filtered(query: "", to: "2026-09-10", calendar: calendar).map(\.id), ["a"])
        XCTAssertEqual(sessions.trainingDays(inWeekOf: day(15), calendar: calendar), ["2026-09-15"])
    }
}
