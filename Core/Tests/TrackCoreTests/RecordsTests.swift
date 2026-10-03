import XCTest
@testable import TrackCore

/// Records as improvements, and the weekly volume series (lib/training-progress.ts, the Progress chart).
final class RecordsTests: XCTestCase {
    private func workout(_ id: String, _ time: Int, _ sets: [(Double, Int)], name: String = "Bench Press") -> Session {
        var session = Session(id: id, name: "W", exercises: [Exercise(name: name, sets: sets.map {
            TrainingSet(kg: $0.0, reps: $0.1, rir: 1, done: true)
        })], splitId: "s", startedAt: time - 1000)
        session.finishedAt = time
        return session
    }

    func testMoreWeightForTheSameRepsOrMoreRepsAtTheSameWeight() {
        let sessions = [workout("a", 1000, [(60, 8)]), workout("b", 2000, [(62.5, 8), (60, 10)]), workout("c", 3000, [(60, 9)])]
        let found = sessions.improvements
        XCTAssertEqual(found.count, 2, "62.5 × 8 beats 60 × 8; 60 × 10 beats 60 × 8; 60 × 9 beats nothing")
        XCTAssertTrue(found.contains { $0.kind == .weight && $0.after.kg == 62.5 && $0.before.kg == 60 })
        XCTAssertTrue(found.contains { $0.kind == .reps && $0.after.reps == 10 && $0.before.reps == 8 })
        XCTAssertEqual(sessions.latestRecords.count, 1, "one row per exercise")
    }

    func testNamesCompareWithoutCaseOrSpaces() {
        let sessions = [workout("a", 1000, [(60, 8)]), workout("b", 2000, [(65, 8)], name: " bench  press ")]
        XCTAssertEqual(sessions.improvements.count, 1)
    }

    func testVolumesEndWithThePresentPeriod() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Bangkok")!
        let now = millis(calendar.date(from: DateComponents(year: 2026, month: 10, day: 2, hour: 12))!)
        let lastWeek = millis(calendar.date(from: DateComponents(year: 2026, month: 9, day: 23, hour: 12))!)
        let sessions = [workout("a", now, [(100, 10)]), workout("b", lastWeek, [(50, 10)])]
        XCTAssertEqual(sessions.volumes(4, per: .week, at: now, calendar: calendar), [0, 0, 500, 1000])
        XCTAssertEqual(sessions.volumes(2, per: .month, at: now, calendar: calendar), [500, 1000])
        XCTAssertEqual(sessions.volumes(3, per: .day, at: now, calendar: calendar), [0, 0, 1000])
    }
}
