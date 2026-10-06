import XCTest
@testable import TrackCore

/// The limits' wording, as the website writes it (lib/data-limits.ts), and that the edges really are allowed.
final class LimitsTests: XCTestCase {
    func testRangesSayTheWholeNumbersAllowed() {
        XCTAssertEqual(Limits.wholeRange(0...Limits.kg, .kg), "0 to 5,000 kg")
        XCTAssertEqual(Limits.wholeRange(0...Limits.kg, .lb), "0 to 11,023 lb")
        XCTAssertEqual(Limits.wholeRange(Limits.bodyweight, .kg), "20 to 400 kg")
        XCTAssertEqual(Limits.wholeRange(Limits.bodyweight, .lb), "45 to 881 lb")
        XCTAssertEqual(Limits.grouped(Limits.reps), "1,000")
    }

    func testTheEdgesTheMessagesNameAreInside() throws {
        let low = try XCTUnwrap(TrainingSet.kilograms(from: "45", unit: .lb)), high = try XCTUnwrap(TrainingSet.kilograms(from: "881", unit: .lb))
        XCTAssertTrue(Limits.bodyweight.contains(low) && Limits.bodyweight.contains(high))
        XCTAssertFalse(Limits.bodyweight.contains(try XCTUnwrap(TrainingSet.kilograms(from: "44", unit: .lb))))
        XCTAssertTrue(TrainingSet(kg: try XCTUnwrap(TrainingSet.kilograms(from: "11023", unit: .lb)), reps: Limits.reps, rir: Limits.rir).isValid)
        XCTAssertFalse(TrainingSet(kg: Limits.kg + 0.01, reps: 1, rir: 0).isValid)
    }
}
