import XCTest
@testable import TrackCore

/// Exercise names to lifts, checked against the website's own list (Fixtures/lift-names.txt, the website's
/// tests/lift-names.txt word for word): the same names give the same lift in both apps.
final class LiftTableTests: XCTestCase {
    func testEveryListedNameMapsToTheWebsitesLiftAndRankGroup() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "lift-names", withExtension: "txt", subdirectory: "Fixtures"))
        let rows = try String(contentsOf: url, encoding: .utf8).split(whereSeparator: \.isNewline)
            .filter { !$0.hasPrefix("#") }.map { $0.split(separator: "|", omittingEmptySubsequences: false).map(String.init) }
        XCTAssertGreaterThan(rows.count, 1000)
        for row in rows {
            let (name, group, id) = (row[0], row[1], row[2])
            let found = LiftTable.detect(name)
            let foundId: String
            switch found { case .lift(let lift): foundId = lift.id; case .ignore: foundId = "ignore"; case .unknown: foundId = "unknown" }
            XCTAssertEqual(foundId, id, name)
            XCTAssertEqual(found.lift.flatMap { $0.at == nil ? nil : $0.group } ?? "-", group, name)
        }
    }

    func testTheTableHoldsTogether() {
        let parts = LiftTable.parts.map(\.part)
        XCTAssertEqual(Set(LiftTable.lifts.map(\.id)).count, LiftTable.lifts.count)
        for lift in LiftTable.lifts {
            XCTAssertTrue(parts.contains(lift.part) && lift.helps.allSatisfy { parts.contains($0) && $0 != lift.part }, lift.id)
            if let at = lift.at { XCTAssertTrue(at.count == 4 && zip(at, at.dropFirst()).allSatisfy { $0 < $1 } && at[0] > 0, lift.id) }
            // `also` adds groups a full-body lift ranks too: parts it already helps, from other groups, only on ranked lifts.
            if let also = lift.also {
                XCTAssertTrue(lift.at != nil && also.allSatisfy(lift.helps.contains) && lift.groups.count == also.count + 1, lift.id)
            }
        }
    }

    func testNamesAreKeyedLikeTheWebsite() {
        XCTAssertEqual(LiftTable.nameKey("  Bench-Press (Paused) "), "bench press paused")
        XCTAssertEqual(LiftTable.nameKey("Farmer\u{2019}s Walk"), "farmers walk")
        XCTAssertEqual(LiftTable.nameKey("D\u{E9}velopp\u{E9} Couch\u{E9}"), "developpe couche")
        XCTAssertEqual(LiftTable.nameKey("squat\u{E41}\u{E1A}\u{E1A}2"), "squat \u{E41}\u{E1A}\u{E1A} 2")
        XCTAssertEqual(LiftTable.nameKey("B\u{F8}jning"), "b\u{F8}jning")
    }

    func testAMovedNameCountsForThatGroupOnItsOwnStandardOrTheGroups() {
        func ranking(_ name: String, _ choice: String? = nil) -> String? {
            LiftTable.ranking(for: name, choices: choice.map { [LiftTable.nameKey(name): $0] } ?? [:])
                .map { "\($0.lift.id) \($0.groups.joined(separator: ","))" }
        }
        XCTAssertNil(ranking("Pec smasher"))
        XCTAssertEqual(ranking("Pec Smasher", "Chest"), "bench-press Chest")
        XCTAssertEqual(ranking("Plank", "Shoulders"), "overhead-press Shoulders")
        XCTAssertEqual(ranking("Cable SLDL", "Back"), "romanian-deadlift Back")
        XCTAssertEqual(ranking("Power clean"), "clean Back,Legs")
        XCTAssertEqual(ranking("Power clean", "Legs"), "clean Legs")
        XCTAssertNil(ranking("Bench press", "none"))
        // Anything else saved (an id from an older build, a group that's gone) is automatic.
        XCTAssertEqual(ranking("Bench press", "chest-fly"), "bench-press Chest")
        XCTAssertEqual(ranking("Bench press", "Core"), "bench-press Chest")
        // Names that happen to be object keys on the website are just names here too.
        XCTAssertNil(ranking("Constructor"))
    }

    func testEachGroupsMainLiftRanksForThatGroup() {
        XCTAssertEqual(Set(LiftTable.file.standards.keys), Set(LiftTable.groups))
        for (group, id) in LiftTable.file.standards {
            XCTAssertTrue(LiftTable.lifts.contains { $0.id == id && $0.at != nil && $0.groups.contains(group) }, group)
        }
    }

    func testSavedChoicesStayWithinTheWebsitesLimits() {
        var training = Training()
        // A long Korean name's key is over twice its length (Hangul splits apart), and still fits.
        training.settings.lifts = [LiftTable.nameKey(String(repeating: "\u{BCA4}\u{CE58}\u{D504}\u{B808}\u{C2A4}", count: 20)): "Chest"]
        XCTAssertTrue(training.isValid)
        training.settings.lifts = Dictionary(uniqueKeysWithValues: (0...Limits.liftChoices).map { ("lift \($0)", "Legs") })
        XCTAssertFalse(training.isValid)
    }
}
