import XCTest

/// Smoothness of the workout screen at a real size (12 exercises of 4 sets): each step's frames and hitches from the
/// app's frame log (App/FrameLog.swift), printed as "PERF step: …". It measures; it doesn't fail on slowness, since
/// a simulator's timing only compares runs with each other. Finding an element reads the whole screen and stalls the
/// app, so each step finds what it needs first and then taps and drags by position only; "calibrate" shows what
/// taps by position cost on their own.
final class PerfTour: XCTestCase {
    private let app = XCUIApplication()

    override func setUp() {
        continueAfterFailure = true
        app.launchArguments = ["-track.storageMode", "local", "-frameLog"]
        app.launchEnvironment["TRACK_SEED"] = bigSeed()
        app.launch()
    }

    func testWorkoutSmoothness() {
        let start = app.buttons["Start workout"].firstMatch
        XCTAssertTrue(start.waitForExistence(timeout: 10))
        let open = at(start)
        measureStep("open workout", settle: 2) { open.tap() }
        let first = app.textFields["Bench Press set 1 weight in kg"]
        XCTAssertTrue(first.waitForExistence(timeout: 5))

        let header = at(app.descendants(matching: .any).matching(NSPredicate(format: "label == 'Bench Press'")).firstMatch)
        let middle = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.55))
        let high = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25))
        let nothing = app.coordinate(withNormalizedOffset: CGVector(dx: 0.03, dy: 0.5))
        measureStep("calibrate: 10 taps on nothing") { for _ in 0..<10 { nothing.tap() } }
        measureStep("scroll down x4") { for _ in 0..<4 { middle.press(forDuration: 0.01, thenDragTo: high, withVelocity: .fast, thenHoldForDuration: 0) } }
        measureStep("scroll up x4") { for _ in 0..<4 { high.press(forDuration: 0.01, thenDragTo: middle, withVelocity: .fast, thenHoldForDuration: 0) } }
        app.swipeDown(velocity: .fast); app.swipeDown(velocity: .fast)

        first.tap()
        let next = at(app.buttons["Next"].firstMatch), keys = ["6", "2", "8"].map { at(app.keys[$0]) }
        measureStep("type 3 digits") { keys.forEach { $0.tap() } }
        measureStep("Next x12") { for _ in 0..<12 { next.tap() } }
        let done = at(app.buttons["Done"].firstMatch)
        measureStep("keyboard away") { done.tap() }

        app.swipeDown(velocity: .fast); app.swipeDown(velocity: .fast)
        let checks = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Bench Press set' AND label ENDSWITH 'Tap to log'"))
        let ticks = (0..<min(3, checks.count)).map { at(checks.element(boundBy: $0)) }
        measureStep("log 3 sets") { ticks.forEach { $0.tap() } }
        measureStep("fold and open a card") { header.tap(); Thread.sleep(forTimeInterval: 0.6); header.tap() }
        measureStep("idle 3s", settle: 3) {}
    }

    /// Where an element is now, to tap later without looking it up again.
    private func at(_ element: XCUIElement) -> XCUICoordinate {
        let frame = element.frame
        return app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: frame.midX, dy: frame.midY))
    }

    /// Runs a step, waits for it to settle, and prints the frames and hitches it took.
    private func measureStep(_ name: String, settle: TimeInterval = 1, _ step: () -> Void) {
        let before = tally()
        step()
        Thread.sleep(forTimeInterval: settle)
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

    /// The demo training with every split made 12 exercises of 4 sets, as a full day's workout.
    private func bigSeed() -> String? {
        guard let json = ProcessInfo.processInfo.environment["TRACK_SEED"],
              var data = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any],
              let splits = data["splits"] as? [[String: Any]] else { return nil }
        let names = ["Bench Press", "Lat pulldown", "Overhead Press", "Barbell curl", "Back squat", "Romanian deadlift",
                     "Incline dumbbell press", "Seated cable row", "Lateral raise", "Triceps pushdown", "Leg press", "Calf raise"]
        data["splits"] = splits.enumerated().map { s, split in
            var split = split
            split["exercises"] = names.enumerated().map { e, name in
                ["id": "p\(s)e\(e)", "name": name,
                 "sets": (0..<4).map { k in ["id": "p\(s)e\(e)s\(k)", "kg": 40, "reps": 8, "rir": 2, "done": false] as [String: Any] }] as [String: Any]
            }
            return split
        }
        return (try? JSONSerialization.data(withJSONObject: data)).flatMap { String(data: $0, encoding: .utf8) }
    }
}
