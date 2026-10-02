import XCTest
@testable import TrackCore

/// Weeks, streaks, levels and the next split, as the website computes them (tests/progress-loop, training tests).
final class MetricsTests: XCTestCase {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Bangkok")!
        return calendar
    }()

    private func at(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12) -> Int {
        millis(calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h))!)
    }

    private func workout(_ time: Int, sets: Int = 3, kg: Double = 50, split: String = "s", id: String = newID()) -> Session {
        var session = Session(id: id, name: "W", exercises: [Exercise(name: "Bench Press", sets: (0..<sets).map { _ in
            TrainingSet(kg: kg, reps: 10, rir: 2, done: true)
        })], splitId: split, startedAt: time - 3_600_000)
        session.finishedAt = time
        return session
    }

    func testWeeksStartOnMondayInLocalTime() {
        // Friday 2 October 2026 → Monday 28 September, midnight.
        XCTAssertEqual(weekStart(at(2026, 10, 2), calendar: calendar), at(2026, 9, 28, 0))
        XCTAssertEqual(weekStart(at(2026, 9, 27), calendar: calendar), at(2026, 9, 21, 0), "Sunday belongs to the week before")
        XCTAssertEqual(dayKey(at(2026, 10, 2), calendar: calendar), "2026-10-02")
    }

    func testStreakCountsWeeksInARowAndForgivesAnEmptyCurrentWeek() {
        let sessions = [workout(at(2026, 9, 14)), workout(at(2026, 9, 22)), workout(at(2026, 9, 29))]
        XCTAssertEqual(sessions.weeklyStreak(at: at(2026, 10, 2), calendar: calendar), 3)
        XCTAssertEqual(sessions.weeklyStreak(at: at(2026, 10, 6), calendar: calendar), 3, "this week has none yet")
        XCTAssertEqual(sessions.weeklyStreak(at: at(2026, 10, 13), calendar: calendar), 0, "a whole week missed")
    }

    func testWeekVolumeComparesWithLastWeekUpToTheSameMoment() {
        let sessions = [workout(at(2026, 9, 22), kg: 100), workout(at(2026, 9, 26), kg: 100), workout(at(2026, 9, 29), kg: 110)]
        let result = sessions.weekVolumeChange(at: at(2026, 9, 30), calendar: calendar)
        XCTAssertEqual(result.volume, 3300)
        XCTAssertEqual(result.change, 10, "against last Mon–Wed only, not the whole of last week")
        XCTAssertNil([workout(at(2026, 9, 29))].weekVolumeChange(at: at(2026, 9, 30), calendar: calendar).change)
    }

    func testLevelsFollowTheDailyCap() {
        XCTAssertEqual(Experience.requirement(for: 1), 100)
        XCTAssertEqual(Experience.requirement(for: 9), 300)
        // 20 start + 3 sets × 5 = 35; a second workout the same day earns sets only, capped at 12 sets a day.
        let day = at(2026, 10, 2, 9)
        let progress = Experience.progress(of: [workout(day, sets: 3, id: "a"), workout(day + 3_600_000, sets: 20, id: "b")], calendar: calendar)
        XCTAssertEqual(progress.total, 35 + 9 * 5)
        XCTAssertEqual(progress.level, 1)
        XCTAssertEqual(progress.current, 80)
    }

    func testNextSplitIsTheOneTrainedLongestAgo() {
        var training = Training()
        training.splits = [Split(id: "a", name: "A", exercises: [Exercise.new(named: "Bench Press")]),
                           Split(id: "b", name: "B", exercises: [Exercise.new(named: "Squat")]),
                           Split(id: "empty", name: "Empty")]
        XCTAssertEqual(training.nextSplit?.split.id, "a", "never trained: list order")
        training.sessions = [workout(at(2026, 9, 29), split: "a")]
        XCTAssertEqual(training.nextSplit?.split.id, "b")
        XCTAssertNil(training.nextSplit?.lastDone)
        training.sessions.append(workout(at(2026, 9, 30), split: "b"))
        XCTAssertEqual(training.nextSplit?.split.id, "a")
        XCTAssertEqual(training.nextSplit?.lastDone, at(2026, 9, 29))
    }

    func testRecordsAreTheHeaviestLoggedWeight() {
        let records = [workout(at(2026, 9, 29), kg: 60), workout(at(2026, 9, 30), kg: 70)].personalRecords
        XCTAssertEqual(records["Bench Press"], 70)
    }
}
