import XCTest
@testable import TrackCore

/// Muscle ranks, worked through by hand against the website's table (lib/muscle-ranks.ts).
final class RankTests: XCTestCase {
    private func session(_ lifts: [(String, Double, Int)]) -> Session {
        var session = Session(name: "W", exercises: lifts.map { name, kg, reps in
            Exercise(name: name, sets: [TrainingSet(kg: kg, reps: reps, rir: 1, done: true)])
        }, splitId: "s", startedAt: 0)
        session.finishedAt = 1
        return session
    }

    func testBenchRanksByEstimatedMaxOverBodyweight() throws {
        // 80 kg × 5: 1RM 93.3, 1.17 × bodyweight → Strong, 42% to Elite; Elite needs 96 kg for 5.
        let chest = try XCTUnwrap([session([("Bench Press", 80, 5)])].muscleRanks(bodyweight: 80).first { $0.muscle == .chest })
        XCTAssertEqual(chest.name, "Strong")
        XCTAssertEqual(chest.progress, 0.4167, accuracy: 0.001)
        XCTAssertEqual(chest.next?.kg, 96)
        XCTAssertEqual(chest.best?.lift, "Bench press")
    }

    func testMachinesCountAtThreeQuartersAndDumbbellsPerSide() throws {
        let ranks = [session([("Lat pulldown", 60, 10), ("Dumbbell curl", 15, 10)])].muscleRanks(bodyweight: 80)
        XCTAssertEqual(ranks.first { $0.muscle == .back }?.name, "Solid", "60 × 10 → 80 1RM × 0.75 = 0.75 × bodyweight")
        XCTAssertEqual(ranks.first { $0.muscle == .arms }?.name, "Strong", "15 kg a side for 10 → 0.25 × bodyweight")
    }

    func testCoreWorkAndHighRepSetsDontRank() {
        let ranks = [session([("Plank", 20, 1), ("Bench Press", 60, 15)])].muscleRanks(bodyweight: 80)
        XCTAssertTrue(ranks.allSatisfy { $0.rank == 0 && $0.best == nil })
    }

    func testTheSpecificMovementWinsOverTheGenericOne() {
        XCTAssertEqual(Ranks.lift(for: "Calf raise in leg press")?.lift, "Calf raise")
        XCTAssertEqual(Ranks.lift(for: "Bulgarian split squat")?.lift, "Lunge")
        XCTAssertEqual(Ranks.lift(for: "Back squat")?.lift, "Squat")
        XCTAssertNil(Ranks.lift(for: "Hanging leg raise"))
    }

    func testEliteIsTheTop() throws {
        let chest = try XCTUnwrap([session([("Bench Press", 140, 3)])].muscleRanks(bodyweight: 80).first { $0.muscle == .chest })
        XCTAssertEqual(chest.name, "Elite")
        XCTAssertEqual(chest.progress, 1)
        XCTAssertNil(chest.next)
    }

    func testABadBodyweightDoesNotCrash() {
        XCTAssertTrue([session([("Bench Press", 80, 5)])].muscleRanks(bodyweight: -70).allSatisfy { $0.rank >= 0 })
    }
}
