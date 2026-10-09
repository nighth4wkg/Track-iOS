import XCTest
@testable import TrackCore

/// Muscle ranks, worked through by hand against the website's (tests/muscle-ranks.test.ts).
final class RankTests: XCTestCase {
    private func session(_ lifts: [(String, Double, Int)]) -> Session {
        var session = Session(name: "W", exercises: lifts.map { name, kg, reps in
            Exercise(name: name, sets: [TrainingSet(kg: kg, reps: reps, rir: 1, done: true)])
        }, splitId: "s", startedAt: 0)
        session.finishedAt = 1
        return session
    }

    private func rank(_ name: String, _ kg: Double, _ reps: Int, bodyweight: Double, _ muscle: Muscle, choices: [String: String] = [:]) throws -> MuscleRank {
        try XCTUnwrap([session([(name, kg, reps)])].muscleRanks(bodyweight: bodyweight, choices: choices).first { $0.muscle == muscle })
    }

    private func score(_ rank: MuscleRank) -> Double { Double(rank.rank) + rank.progress }

    func testTheGroupsMatchTheTable() {
        XCTAssertEqual(Muscle.allCases.map(\.rawValue), LiftTable.groups)
    }

    func testBenchRanksByEstimatedMaxOverBodyweight() throws {
        // 80 kg × 5: 1RM 93.3, 1.17 × bodyweight → Strong, 42% to Elite; Elite needs 96 kg for 5.
        let chest = try rank("Bench Press", 80, 5, bodyweight: 80, .chest)
        XCTAssertEqual(chest.name, "Strong")
        XCTAssertEqual(chest.progress, 0.4167, accuracy: 0.001)
        XCTAssertEqual(chest.next?.kg, 96)
        XCTAssertEqual(chest.best?.lift, "Bench press")
        XCTAssertEqual(chest.best?.kind, .weight)
    }

    func testMachinesCountAtThreeQuartersAndDumbbellsPerSide() throws {
        XCTAssertEqual(try rank("Lat pulldown", 60, 10, bodyweight: 80, .back).name, "Solid", "60 × 10 → 80 1RM × 0.75 = 0.75 × bodyweight")
        XCTAssertEqual(try rank("Dumbbell curl", 15, 10, bodyweight: 80, .arms).name, "Strong", "15 kg a side for 10 → 0.25 × bodyweight")
        XCTAssertEqual(score(try rank("Hammer Strength row", 40, 6, bodyweight: 60, .back)), score(try rank("Machine row", 40, 6, bodyweight: 60, .back)))
    }

    func testCoreCardioAndHighRepSetsDontRank() {
        let ranks = [session([("Plank", 20, 1), ("Treadmill", 5, 1), ("Bench Press", 60, 15)])].muscleRanks(bodyweight: 80)
        XCTAssertTrue(ranks.allSatisfy { $0.rank == 0 && $0.best == nil })
    }

    func testPairsCountBothDumbbellsAndTwoHandedImplementsShareASide() throws {
        // Incline press, 30 kg dumbbells: 2 × 30 × 1.3 = 78 kg on the barbell standard.
        XCTAssertEqual(score(try rank("Incline dumbbell press", 30, 1, bodyweight: 80, .chest)), score(try rank("Incline bench press", 78, 1, bodyweight: 80, .chest)), accuracy: 1e-9)
        XCTAssertEqual(score(try rank("Rope hammer curl", 30, 8, bodyweight: 80, .arms)), score(try rank("Cable curl", 30, 8, bodyweight: 80, .arms)))
        XCTAssertEqual(score(try rank("1-arm cable row", 30, 8, bodyweight: 60, .back)), score(try rank("Cable row", 60, 8, bodyweight: 60, .back)))
    }

    func testBodyweightLiftsCountTheBodyPlusAddedOrMinusAssistance() throws {
        // Pull-up: 80 × (1 + 8/30) = 101.3, 1.27 × bodyweight → Solid.
        let plain = try rank("Pull-up", 0, 8, bodyweight: 80, .back)
        XCTAssertEqual(plain.name, "Solid")
        XCTAssertEqual(plain.best?.kind, .added)
        let helped = try rank("Assisted pull-up machine", 20, 8, bodyweight: 80, .back)
        XCTAssertEqual(helped.best?.kind, .assisted)
        XCTAssertLessThan(score(helped), score(plain))
        let lessHelp = try XCTUnwrap(helped.next?.kg)
        XCTAssertLessThan(lessHelp, 20)
        XCTAssertEqual(try rank("Assisted pull-up machine", lessHelp, 8, bodyweight: 80, .back).rank, helped.rank + 1)
        XCTAssertEqual(try rank("Pull-up", try XCTUnwrap(plain.next?.kg), 8, bodyweight: 80, .back).rank, plain.rank + 1)
        XCTAssertNil(try rank("Assisted dip", 90, 5, bodyweight: 80, .chest).best)
    }

    func testTheNextTargetReachesTheNextRank() throws {
        for (name, muscle) in [("Bench Press", Muscle.chest), ("Machine shoulder press", .shoulders), ("One-Legged Leg Extension", .legs),
                               ("Dumbbell row", .back), ("Incline dumbbell press", .chest), ("Dips", .chest), ("Power clean", .back)] {
            let now = try rank(name, 10, 8, bodyweight: 75, muscle)
            let next = try XCTUnwrap(now.next, name)
            XCTAssertEqual(try rank(name, next.kg, next.reps, bodyweight: 75, muscle).rank, now.rank + 1, name)
        }
    }

    func testFullBodyBarbellLiftsCountTowardEachGroupTheyTrain() throws {
        // 80 kg lifter: power clean 80 (1.0× bodyweight, Solid on 0.45/0.75/1.05/1.5), snatch 60 (0.75×, Solid on 0.36/0.6/0.84/1.2).
        let ranked = { (name: String, kg: Double) in [self.session([(name, kg, 1)])].muscleRanks(bodyweight: 80).filter { $0.best != nil } }
        XCTAssertEqual(ranked("Power clean", 80).map { "\($0.muscle) \($0.rank)" }, ["\(Muscle.back) 2", "\(Muscle.legs) 2"])
        XCTAssertEqual(ranked("Snatch", 60).map { "\($0.muscle) \($0.rank)" }, ["\(Muscle.back) 2", "\(Muscle.shoulders) 2", "\(Muscle.legs) 2"])
        // Each group keeps its own best: a bigger squat takes Legs, the clean still holds Back.
        let both = [session([("Power clean", 80, 1), ("Back squat", 160, 1)])].muscleRanks(bodyweight: 80)
        XCTAssertEqual(both.first { $0.muscle == .legs }?.best?.lift, "Squat")
        XCTAssertEqual(both.first { $0.muscle == .back }?.best?.lift, "Clean")
        for name in ["Kettlebell clean", "Dumbbell snatch", "Kettlebell swing", "Clean pull"] {
            XCTAssertTrue([session([(name, 40, 5)])].muscleRanks(bodyweight: 80).allSatisfy { $0.best == nil }, name)
        }
    }

    func testAChoiceRanksAnUnknownNameOrStopsAKnownOneCounting() throws {
        XCTAssertNil(try rank("Pec smasher", 100, 1, bodyweight: 80, .chest).best)
        let chosen = try rank("Pec smasher", 100, 1, bodyweight: 80, .chest, choices: [LiftTable.nameKey("Pec smasher"): "bench-press"])
        XCTAssertEqual(chosen.name, "Strong")
        XCTAssertNil(try rank("Bench press", 100, 1, bodyweight: 80, .chest, choices: [LiftTable.nameKey("Bench press"): "none"]).best)
    }

    func testEliteIsTheTop() throws {
        let chest = try rank("Bench Press", 140, 3, bodyweight: 80, .chest)
        XCTAssertEqual(chest.name, "Elite")
        XCTAssertEqual(chest.progress, 1)
        XCTAssertNil(chest.next)
    }

    func testABadBodyweightDoesNotCrash() {
        XCTAssertTrue([session([("Bench Press", 80, 5), ("Pull-up", 0, 5)])].muscleRanks(bodyweight: -70).allSatisfy { $0.rank >= 0 })
    }
}
