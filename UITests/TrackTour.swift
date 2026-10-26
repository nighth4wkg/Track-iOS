import XCTest

/// Every screen and flow, used as a person would, with a screenshot at each step ("NN-what") to check by eye: the
/// looks, the motion caught mid-way, and what each tap did. It doesn't stop on something missing: it prints
/// "TOUR missing: …" and carries on, so one run shows everything, then fails if anything was missing.
final class TrackTour: XCTestCase {
    private let app = XCUIApplication()
    private var step = 0
    private var missing: [String] = []

    override func setUp() {
        continueAfterFailure = true
        app.launchArguments = ["-track.storageMode", "local"]
        app.launchEnvironment["TRACK_SEED"] = ProcessInfo.processInfo.environment["TRACK_SEED"]
        app.launch()
    }

    override func tearDown() { XCTAssertEqual(missing, [], "steps the tour couldn't do") }

    /// Every screen of the recoded app, each kept as a screenshot: Home, a workout (keypad, every set ticked, the
    /// picker, an exercise's options), the recap, History and a past workout, Progress and a lift, Rank, Settings, a split.
    func testTour() {
        snap("home")
        app.swipeUp(); snap("home-scrolled"); app.swipeDown()

        tap(app.buttons["Start workout"].firstMatch, "Start workout"); snap("workout", after: 1)
        tap(app.buttons["Reps in reserve, Set 1"].firstMatch, "set 1 RIR"); snap("keypad", after: 0.8)
        tap(app.buttons["Done"].firstMatch, "keypad Done"); snap("keypad-gone", after: 0.6)
        app.swipeUp(); app.swipeUp()
        tap(app.buttons["Add exercise"].firstMatch, "Add exercise"); snap("picker", after: 1)
        // The sheet's title row (Done) scrolls with it, as the PWA's: back to the top first.
        app.swipeUp(); snap("picker-scrolled"); app.swipeDown(); dismissSheet(); app.swipeDown(); app.swipeDown()
        tap(app.buttons.matching(NSPredicate(format: "label ENDSWITH ' options'")).firstMatch, "exercise options")
        snap("exercise-options", after: 0.8); dismissSheet()
        tickEverySet(); snap("all-ticked", after: 1)
        tap(app.buttons["Finish workout"].firstMatch, "Finish"); snap("recap", after: 1.5)
        app.swipeUp(); snap("recap-scrolled")
        tap(app.buttons["Continue"].firstMatch, "Continue"); snap("home-after", after: 1)

        tap(app.buttons["History"].firstMatch, "History"); snap("history", after: 0.8)
        app.swipeUp(); snap("history-scrolled"); app.swipeDown()
        tap(app.buttons.matching(NSPredicate(format: "label CONTAINS 'Full body'")).firstMatch, "a past workout"); snap("session", after: 1)
        app.swipeUp(); snap("session-scrolled"); back("session")

        tap(app.buttons["Progress"].firstMatch, "Progress"); snap("progress", after: 0.8)
        app.swipeUp(); snap("progress-scrolled")
        let lift = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Bench Press'")).firstMatch
        if !lift.isHittable { app.swipeUp() }
        tap(lift, "a lift"); snap("lift", after: 1)
        app.swipeUp(); snap("lift-scrolled"); back("lift")

        tap(app.buttons["Rank"].firstMatch, "Rank"); snap("rank", after: 0.8)
        app.swipeUp(); snap("rank-scrolled"); app.swipeDown()

        tap(app.buttons["Home"].firstMatch, "Home")
        tap(app.buttons["Settings"].firstMatch, "Settings"); snap("settings", after: 0.8)
        app.swipeUp(); snap("settings-scrolled"); app.swipeUp(); snap("settings-bottom")
        app.swipeDown(); app.swipeDown(); tap(app.buttons["Done"].firstMatch, "Settings Done")
        tap(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Upper'")).firstMatch, "a split"); snap("split", after: 1)
        app.swipeUp(); snap("split-scrolled"); back("split"); snap("home-end", after: 0.6)
    }

    /// Ticks every set, as Finish needs (test data only): the next exercise opens as one finishes.
    private func tickEverySet() {
        let mark = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Mark ' AND label ENDSWITH ' done'")).firstMatch
        var asked = false
        for _ in 0..<60 {
            guard mark.waitForExistence(timeout: 1) else { return }
            if !mark.isHittable { app.swipeUp() }
            mark.tap()
            if !asked { allowNotificationsIfAsked(); asked = true }
        }
        missing.append("tick every set"); print("TOUR missing: tick every set")
    }

    /// Back from a page: its title bar scrolls with it, so up to the top first.
    private func back(_ page: String) {
        app.swipeDown(); app.swipeDown()
        tap(app.buttons["Back"].firstMatch, "back from \(page)")
    }

    /// The top sheet's Done.
    private func dismissSheet() {
        tap(app.buttons["Done"].firstMatch, "sheet Done")
        Thread.sleep(forTimeInterval: 0.6)
    }

    /// A first install with pounds: the welcome, every empty screen, the new-split sheet (templates), a split of
    /// one exercise, and a first workout typed in on the keyboard, to its recap.
    func testFirstRun() {
        app.terminate()
        var seed = (try? JSONSerialization.jsonObject(with: Data((ProcessInfo.processInfo.environment["TRACK_SEED"] ?? "{}").utf8))) as? [String: Any] ?? [:]
        seed["splits"] = []; seed["sessions"] = []; seed["active"] = NSNull(); seed["restUntil"] = NSNull()
        var settings = seed["settings"] as? [String: Any] ?? [:]
        settings["unit"] = "lb"; settings["bodyweight"] = NSNull()
        seed["settings"] = settings
        app.launchArguments = []
        app.launchEnvironment["TRACK_SEED"] = String(data: try! JSONSerialization.data(withJSONObject: seed), encoding: .utf8)
        app.launch()
        snap("welcome", after: 1)
        tap(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Sync with an account'")).firstMatch, "sync"); snap("sync-soon")
        tap(app.buttons["Continue locally"].firstMatch, "Continue locally"); snap("empty-home", after: 1)
        for tab in ["History", "Progress", "Rank"] { tap(app.buttons[tab].firstMatch, tab); snap("empty-\(tab)", after: 0.8) }
        tap(app.buttons["Home"].firstMatch, "Home")

        tap(app.buttons["New split"].firstMatch, "New split"); snap("new-split", after: 0.8)
        tap(app.textFields.firstMatch, "split name"); app.typeText("Arms")
        tap(app.buttons["Create"].firstMatch, "Create"); snap("split-new", after: 1)
        tap(app.buttons["Add exercise"].firstMatch, "Add exercise")
        tap(app.textFields.matching(NSPredicate(format: "placeholderValue == 'Search exercises'")).firstMatch, "search")
        app.typeText("Barbell curl")
        tap(app.buttons["Add Barbell curl"].firstMatch, "Add Barbell curl"); snap("picker-added", after: 0.8)
        dismissSheet(); snap("split-one-exercise"); back("split")

        tap(app.buttons["Start workout"].firstMatch, "Start"); snap("first-workout", after: 1)
        tap(app.buttons["lb, Set 1"].firstMatch, "set 1 lb")
        for value in ["60", "10", "2", "60", "10", "2", "60", "10", "2"] {
            app.typeKeys(value)
            if app.buttons["Next"].firstMatch.exists { app.buttons["Next"].firstMatch.tap() }
        }
        allowNotificationsIfAsked(); snap("first-typed", after: 1)
        if app.buttons["Done"].firstMatch.exists { app.buttons["Done"].firstMatch.tap() }
        tickEverySet(); snap("first-ticked", after: 1)
        tap(app.buttons["Finish workout"].firstMatch, "Finish"); snap("first-recap", after: 1.5)
        tap(app.buttons["Continue"].firstMatch, "Continue"); snap("home-after-first", after: 1)
        for tab in ["History", "Progress", "Rank"] { tap(app.buttons[tab].firstMatch, tab); snap("first-\(tab)", after: 0.8) }
    }

    private func snap(_ name: String, after delay: TimeInterval = 0.5) {
        if delay > 0 { Thread.sleep(forTimeInterval: delay) }
        step += 1
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = String(format: "%02d-%@", step, name)
        shot.lifetime = .keepAlways
        add(shot)
    }

    private func tap(_ element: XCUIElement, _ what: String) {
        if element.waitForExistence(timeout: 4), element.isHittable { element.tap() } else { missing.append(what); print("TOUR missing: \(what) (step \(step))") }
    }
}
