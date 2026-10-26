import XCTest

/// The exercise list's scroll, which the owner feels lag (the phone's frame log agrees: worst there), with the workout
/// page's scroll first to compare: 20 s of finger drags each, 4 s still around each, for profile.yml's Time Profiler.
/// Prints each scroll's frames and hitches ("PERF …"); it measures, it doesn't fail on slowness. During the drags it
/// only drags by position: finding an element reads the whole screen and stalls the app.
final class ScrollProfile: XCTestCase {
    private let app = XCUIApplication()

    override func setUp() {
        continueAfterFailure = true
        app.launchArguments = ["-track.storageMode", "local", "-frameLog"]
        app.launchEnvironment["TRACK_SEED"] = ProcessInfo.processInfo.environment["TRACK_SEED"]
        app.launch()
    }

    func testExerciseListScroll() {
        let start = app.buttons["Start workout"].firstMatch
        XCTAssertTrue(start.waitForExistence(timeout: 10))
        start.tap()
        let add = app.buttons["Add exercise"].firstMatch
        XCTAssertTrue(add.waitForExistence(timeout: 5))
        Thread.sleep(forTimeInterval: 4)
        measure("workout page") { drags(for: 20) }

        for _ in 0..<8 where !add.isHittable { app.swipeUp() }
        add.tap()
        Thread.sleep(forTimeInterval: 4)
        measure("exercise list") { drags(for: 20) }
    }

    /// Down, up, down… at a finger's pace, from the lower to the upper part of the screen and back, for this long.
    private func drags(for seconds: TimeInterval) {
        let low = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8))
        let high = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3))
        let pace = XCUIGestureVelocity(rawValue: 750) // points a second, as the phone runs were
        let end = Date().addingTimeInterval(seconds)
        var down = true
        while Date() < end {
            (down ? low : high).press(forDuration: 0.05, thenDragTo: down ? high : low, withVelocity: pace, thenHoldForDuration: 0)
            down.toggle()
        }
    }

    /// Runs it, waits 4 s still, and prints the frames and hitches it took.
    private func measure(_ name: String, _ step: () -> Void) {
        let before = tally()
        step()
        Thread.sleep(forTimeInterval: 4)
        let after = tally()
        let delta = { (key: String) in after[key, default: 0] - before[key, default: 0] }
        print(String(format: "PERF %@: %.0f frames, jank %.0f (%.0f ms late); all hitches %.0f (%.0f ms late)",
                     name, delta("frames"), delta("jank"), delta("jankms"), delta("hitches"), delta("late")))
    }

    private func tally() -> [String: Double] {
        let label = app.otherElements["frame-log"].firstMatch.label
        if label.isEmpty { XCTFail("no frame log") }
        return Dictionary(uniqueKeysWithValues: label.split(separator: " ").compactMap { pair in
            let parts = pair.split(separator: "=")
            return parts.count == 2 ? (String(parts[0]), Double(parts[1]) ?? 0) : nil
        })
    }
}
