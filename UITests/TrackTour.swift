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
        tap(app.buttons["Add exercise"].firstMatch, "Add exercise"); snap("picker", after: 1)
        app.swipeUp(); snap("picker-scrolled"); dismissSheet()
        tap(app.buttons.matching(NSPredicate(format: "label ENDSWITH ' options'")).firstMatch, "exercise options")
        snap("exercise-options", after: 0.8); dismissSheet()
        tickEverySet(); snap("all-ticked", after: 1)
        tap(app.buttons["Finish workout"].firstMatch, "Finish"); snap("recap", after: 1.5)
        app.swipeUp(); snap("recap-scrolled")
        tap(app.buttons["Continue"].firstMatch, "Continue"); snap("home-after", after: 1)

        tap(app.buttons["History"].firstMatch, "History"); snap("history", after: 0.8)
        app.swipeUp(); snap("history-scrolled"); app.swipeDown()
        tap(app.buttons.matching(NSPredicate(format: "label CONTAINS 'Full body'")).firstMatch, "a past workout"); snap("session", after: 1)
        app.swipeUp(); snap("session-scrolled"); tap(app.buttons["Back"].firstMatch, "back from session")

        tap(app.buttons["Progress"].firstMatch, "Progress"); snap("progress", after: 0.8)
        app.swipeUp(); snap("progress-scrolled")
        tap(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Bench Press'")).firstMatch, "a lift"); snap("lift", after: 1)
        app.swipeUp(); snap("lift-scrolled"); tap(app.buttons["Back"].firstMatch, "back from lift")

        tap(app.buttons["Rank"].firstMatch, "Rank"); snap("rank", after: 0.8)
        app.swipeUp(); snap("rank-scrolled"); app.swipeDown()

        tap(app.buttons["Home"].firstMatch, "Home")
        tap(app.buttons["Settings"].firstMatch, "Settings"); snap("settings", after: 0.8)
        app.swipeUp(); snap("settings-scrolled"); app.swipeUp(); snap("settings-bottom")
        tap(app.buttons["Done"].firstMatch, "Settings Done")
        tap(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Upper'")).firstMatch, "a split"); snap("split", after: 1)
        app.swipeUp(); snap("split-scrolled"); tap(app.buttons["Back"].firstMatch, "back from split"); snap("home-end", after: 0.6)
    }

    /// Ticks every set, opening each closed exercise in turn, as Finish needs (test data only).
    private func tickEverySet() {
        let mark = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Mark ' AND label ENDSWITH ' done'")).firstMatch
        let closed = app.buttons.matching(NSPredicate(format: "value == 'Closed'")).firstMatch
        var asked = false
        for _ in 0..<60 {
            if mark.exists {
                if !mark.isHittable { app.swipeUp() }
                mark.tap()
                if !asked { allowNotificationsIfAsked(); asked = true }
            } else if closed.exists {
                if !closed.isHittable { app.swipeUp() }
                closed.tap()
            } else { return }
        }
        missing.append("tick every set"); print("TOUR missing: tick every set")
    }

    /// A tap outside the top sheet, as a person closes it.
    private func dismissSheet() {
        let outside = app.descendants(matching: .any)["Dismiss"].firstMatch
        if outside.waitForExistence(timeout: 2) { outside.tap() } else { app.swipeDown() }
        Thread.sleep(forTimeInterval: 0.6)
    }

    /// A first install, in light mode with pounds and ✓-only logging: the welcome, every empty screen, a template,
    /// and a first workout to its recap.
    func testFirstRun() {
        app.terminate()
        var seed = (try? JSONSerialization.jsonObject(with: Data((ProcessInfo.processInfo.environment["TRACK_SEED"] ?? "{}").utf8))) as? [String: Any] ?? [:]
        seed["splits"] = []; seed["sessions"] = []; seed["active"] = NSNull(); seed["restUntil"] = NSNull()
        var settings = seed["settings"] as? [String: Any] ?? [:]
        settings["theme"] = "light"; settings["logSets"] = "manual"; settings["unit"] = "lb"; settings["bodyweight"] = NSNull()
        seed["settings"] = settings
        app.launchArguments = []
        app.launchEnvironment["TRACK_SEED"] = String(data: try! JSONSerialization.data(withJSONObject: seed), encoding: .utf8)
        app.launch()
        snap("welcome", after: 1)
        tap(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Sync across'")).firstMatch, "sync card"); snap("sync-soon")
        tap(app.buttons["Not now"], "Not now")
        tap(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Keep it on'")).firstMatch, "local card"); snap("empty-home", after: 1)
        for tab in ["History", "Progress", "Rank"] { tap(app.tabBars.buttons[tab], tab); snap("empty-\(tab)", after: 0.8) }
        tap(app.textFields["Bodyweight"], "bodyweight field"); app.typeText("165"); snap("rank-bodyweight-typed")
        tap(app.buttons["Save"].firstMatch, "save bodyweight"); snap("rank-unranked", after: 1)
        tap(app.tabBars.buttons["Home"], "Home")
        tap(app.buttons["Push"].firstMatch, "Push template"); snap("template-added", after: 1)
        tap(app.buttons["Start workout"].firstMatch, "Start"); allowNotificationsIfAsked(); snap("first-workout", after: 1)
        tap(check("Bench Press set 1"), "✓ empty set"); snap("tick-empty-set", after: 0.8)
        let kg = app.buttons["Bench Press set 1 weight in lb"]
        tap(kg, "lb field"); app.typeKeys("135"); app.buttons["Bench Press set 1 reps"].tap(); app.typeKeys("10")
        app.buttons["Bench Press set 1 RIR"].tap(); app.typeKeys("2"); snap("manual-typed-not-logged", after: 1)
        tap(check("Bench Press set 1"), "✓ set 1"); allowNotificationsIfAsked(); snap("manual-ticked", after: 0.8)
        tap(app.buttons["Done"].firstMatch, "keyboard Done")
        tap(app.buttons["Finish workout"].firstMatch, "Finish"); tap(app.buttons["dialog-action"], "confirm"); snap("first-recap", after: 1.5)
        tap(app.buttons["Continue"].firstMatch, "Continue"); snap("first-progress", after: 1)
        tap(app.tabBars.buttons["History"], "History"); snap("first-history", after: 0.8)
        tap(app.tabBars.buttons["Rank"], "Rank"); snap("first-rank", after: 0.8)
        tap(app.tabBars.buttons["Home"], "Home"); snap("home-after-first", after: 0.8)
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

    private func check(_ set: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", set + ":")).firstMatch
    }
}
