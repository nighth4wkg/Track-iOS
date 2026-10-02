import XCTest
@testable import TrackCore

/// The website's own saved data (Fixtures/web-state.json, checked by the website's schema when exported) must read
/// here and write back the same, so a copy can move between the iPhone and the website without losing anything.
final class TrainingCodingTests: XCTestCase {
    private func fixture() throws -> Data {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "web-state", withExtension: "json", subdirectory: "Fixtures"))
        return try Data(contentsOf: url)
    }

    func testReadsTheWebsitesData() throws {
        let training = try TrainingFile.decode(fixture())
        XCTAssertEqual(training.sessions.count, 24)
        XCTAssertEqual(training.splits.count, 2)
        XCTAssertEqual(training.sessions[0].notes, "Felt strong")
        XCTAssertEqual(training.sessions[0].exercises[0].sets[0].side, .left)
        XCTAssertEqual(training.settings.logSets, .manual)
        XCTAssertEqual(training.settings.bodyweight, 72)
        XCTAssertNil(training.active?.finishedAt)
        XCTAssertNil(training.active?.exercises[0].sets[0].kg)
    }

    func testWritesBackTheSameJSON() throws {
        let original = try JSONSerialization.jsonObject(with: fixture()) as! NSDictionary
        let written = try JSONSerialization.jsonObject(with: TrainingFile.encode(TrainingFile.decode(fixture()))) as! NSDictionary
        XCTAssertEqual(written, original, "every key and null comes back exactly as the website wrote it")
    }

    func testEmptyFieldsAreNullNotMissing() throws {
        var training = Training()
        training.active = Session(name: "Upper", exercises: [Exercise(name: "Bench Press", sets: [TrainingSet()])], splitId: "s", startedAt: 1)
        let json = try XCTUnwrap(String(data: TrainingFile.encode(training), encoding: .utf8))
        XCTAssertTrue(json.contains("\"restUntil\":null"))
        XCTAssertTrue(json.contains("\"finishedAt\":null"))
        XCTAssertTrue(json.contains("\"kg\":null"))
        XCTAssertFalse(json.contains("\"side\""), "two-sided sets carry no side")
        XCTAssertFalse(json.contains("\"editedAt\""))
    }

    func testOlderCopiesWithoutQuestVersionReadAsZero() throws {
        let json = #"{"version":1,"splits":[],"sessions":[],"active":null,"restUntil":null,"settings":{"unit":"kg","weeklyGoal":3,"restSeconds":90,"theme":"system"}}"#
        XCTAssertEqual(try TrainingFile.decode(Data(json.utf8)).questVersion, 0)
    }

    func testSavesAndLoadsAFile() throws {
        let file = TrainingFile(url: FileManager.default.temporaryDirectory.appendingPathComponent("\(newID()).json"))
        XCTAssertEqual(try file.load(), Training(), "no file yet is a fresh start")
        var training = Training()
        training.splits = [Split(name: "Upper")]
        try file.save(training)
        XCTAssertEqual(try file.load(), training)
        try? FileManager.default.removeItem(at: file.url)
    }

    func testIdentifiersLookLikeTheWebsites() {
        let id = newID()
        XCTAssertEqual(id, id.lowercased())
        XCTAssertEqual(id.count, 36)
    }
}
