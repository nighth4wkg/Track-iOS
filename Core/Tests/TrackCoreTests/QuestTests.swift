import XCTest
@testable import TrackCore

/// Achievements, as the website awards them (lib/training-quests.ts).
final class QuestTests: XCTestCase {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Bangkok")!
        return calendar
    }()

    private func workout(day: Int, sets: Int = 4, kg: Double = 50) -> Session {
        let time = millis(calendar.date(from: DateComponents(year: 2026, month: 9, day: day, hour: 18))!)
        var session = Session(name: "W", exercises: [Exercise(name: "Bench Press", sets: (0..<sets).map { _ in
            TrainingSet(kg: kg, reps: 8, rir: 2, done: true)
        })], splitId: "s", startedAt: time - 3_600_000)
        session.finishedAt = time
        return session
    }

    func testThreeWorkoutsInAWeekEarnTheEasyOnesOnTheLatest() throws {
        var training = Training()
        training.sessions = [workout(day: 28), workout(day: 29), workout(day: 30)].reversed()
        training.awardLatestQuests(calendar: calendar)
        let latest = try XCTUnwrap(training.sessions.first { $0.finishedAt == training.sessions.compactMap(\.finishedAt).max() })
        XCTAssertEqual(Set(latest.questAwards?.map(\.questId) ?? []),
                       ["first-session", "ten-sets", "two-sessions", "three-days", "three-in-week"])
        XCTAssertEqual(latest.questAwards?.reduce(0) { $0 + $1.xp }, 20 + 25 + 30 + 30 + 40)
        XCTAssertTrue(training.sessions.allSatisfy { $0.xpEarned != nil }, "training XP is fixed once awarded")
        XCTAssertEqual(training.sessions.first { $0.id != latest.id && $0.finishedAt! < latest.finishedAt! && $0.xpEarned == 40 } != nil, true,
                       "a day's first workout: 20 + 4 sets × 5")
    }

    func testAnAchievementIsAwardedOnce() {
        var training = Training()
        training.sessions = [workout(day: 28)]
        training.awardLatestQuests(calendar: calendar)
        training.sessions.insert(workout(day: 29), at: 0)
        training.awardLatestQuests(calendar: calendar)
        let ids = training.sessions.flatMap { ($0.questAwards ?? []).map(\.questId) }
        XCTAssertEqual(ids.filter { $0 == "first-session" }.count, 1)
        XCTAssertTrue(ids.contains("two-sessions"))
    }

    func testARecordAfterAPriorResultCounts() {
        var training = Training()
        training.sessions = [workout(day: 29, kg: 55), workout(day: 28, kg: 50)]
        training.awardLatestQuests(calendar: calendar)
        XCTAssertTrue(training.sessions.flatMap { ($0.questAwards ?? []).map(\.questId) }.contains("first-record"))
    }

    func testNearestIsTheFurthestAlongNotYetEarned() throws {
        var training = Training()
        training.sessions = [workout(day: 28)]
        training.awardLatestQuests(calendar: calendar)
        let nearest = try XCTUnwrap(training.sessions.nearestQuest(calendar: calendar))
        XCTAssertNil(training.sessions.questAwards[nearest.quest.id])
        XCTAssertEqual(nearest.quest.id, "two-sessions", "1 of 2 workouts is the furthest along")
        XCTAssertEqual(nearest.value, 1)
    }
}
