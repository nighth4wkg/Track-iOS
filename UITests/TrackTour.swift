import XCTest

/// Every screen and flow, used as a person would, with a screenshot at each step ("NN-what") to check by eye: the
/// looks, the motion caught mid-way, and what each tap did. It never stops on something missing; it prints
/// "TOUR missing: …" and carries on, so one run shows everything.
final class TrackTour: XCTestCase {
    private let app = XCUIApplication()
    private var step = 0

    override func setUp() {
        continueAfterFailure = true
        app.launchArguments = ["-track.storageMode", "local"]
        app.launchEnvironment["TRACK_SEED"] = ProcessInfo.processInfo.environment["TRACK_SEED"]
        app.launch()
    }

    func testTour() {
        snap("home")
        app.swipeUp(); snap("home-scrolled"); app.swipeDown()

        // A workout, from the start.
        tap(app.buttons["Start workout"].firstMatch, "Start workout")
        snap("start-0.1s", after: 0.1); snap("start-settled", after: 1)
        let rir1 = app.textFields["Bench Press set 1 RIR"]
        tap(rir1, "set 1 RIR"); snap("rir-tapped-not-logged", after: 1)
        rir1.typeText("2"); snap("rir-typed", after: 0.1); snap("rir-saved", after: 1)
        allowNotificationsIfAsked(); snap("resting")
        tap(app.textFields["Bench Press set 1 reps"], "set 1 reps")
        app.typeText("9"); snap("logged-set-edited", after: 1)
        tap(app.buttons["Done"].firstMatch, "keyboard Done"); snap("keyboard-gone")
        for n in 2...3 { tap(check("Bench Press set \(n)"), "✓ set \(n)"); snap("ticked-\(n)", after: 0.15) }
        snap("bench-folded", after: 1)
        tap(check("Bench Press set 3"), "untick after fold"); snap("untick-folded-card", after: 0.6)
        tap(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Bench Press' AND NOT label CONTAINS 'set'")).firstMatch, "open folded card"); snap("folded-opened", after: 0.6)
        tap(check("Bench Press set 3"), "untick set 3"); snap("unticked", after: 0.8)
        tap(check("Bench Press set 3"), "retick set 3"); snap("reticked", after: 1)

        let next = app.textFields.matching(NSPredicate(format: "label ENDSWITH 'set 1 RIR' AND NOT label BEGINSWITH 'Bench'")).firstMatch
        if next.waitForExistence(timeout: 3) {
            next.swipeLeft(); snap("set-delete-armed", after: 0.5); next.swipeRight(); snap("set-delete-disarmed", after: 0.5)
        }
        tap(app.buttons["Add set"].firstMatch, "Add set"); snap("set-added", after: 0.6)
        app.swipeUp(); snap("workout-scrolled"); app.swipeUp(); snap("workout-bottom")
        tap(app.buttons.matching(NSPredicate(format: "label ENDSWITH 'workout options'")).firstMatch, "workout options")
        snap("workout-options", after: 0.8); tap(app.buttons["Close"].firstMatch, "close options"); snap("options-closed", after: 0.8)

        app.swipeDown(); app.swipeDown(); snap("workout-top")
        let lat = app.descendants(matching: .any)["Lat pulldown"].firstMatch, press = app.descendants(matching: .any)["Overhead Press"].firstMatch
        if lat.waitForExistence(timeout: 3), press.exists {
            lat.press(forDuration: 1.2, thenDragTo: press, withVelocity: .slow, thenHoldForDuration: 0.8)
            snap("dropped-0.1s", after: 0.1); snap("dropped-settled", after: 1)
            print("TOUR order: \(app.descendants(matching: .any).matching(NSPredicate(format: "label IN %@", ["Lat pulldown", "Overhead Press"])).allElementsBoundByIndex.map { "\($0.label)@\(Int($0.frame.minY))" })")
        } else { print("TOUR missing: drag") }
        tap(app.buttons["Keep for later"], "Keep for later"); snap("home-in-progress", after: 1)
        tap(app.buttons.matching(NSPredicate(format: "label CONTAINS 'Resume workout'")).firstMatch, "Resume"); snap("resumed", after: 1)
        tap(app.buttons["Finish workout"].firstMatch, "Finish workout"); snap("finish-confirm", after: 0.6)
        tap(app.buttons["dialog-action"], "confirm finish"); snap("recap", after: 1.5)
        app.swipeUp(); snap("recap-scrolled")
        tap(app.buttons["Continue"].firstMatch, "Continue"); snap("progress", after: 1)

        // The tabs.
        for period in ["D", "M", "W"] { tap(app.buttons[period].firstMatch, period); snap("progress-\(period)", after: 0.6) }
        app.swipeUp(); snap("progress-scrolled"); app.swipeDown()
        tap(app.tabBars.buttons["Rank"], "Rank"); snap("rank", after: 0.8)
        tap(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Bodyweight'")).firstMatch, "bodyweight"); snap("bodyweight", after: 0.8)
        tap(app.buttons["Close"].firstMatch, "close bodyweight")
        app.swipeUp(); snap("rank-scrolled"); app.swipeDown()
        tap(app.tabBars.buttons["History"], "History"); snap("history", after: 0.8)
        tap(app.buttons["Filter by date"].firstMatch, "date filter"); snap("history-filter", after: 0.8)
        tap(app.buttons["Any"].firstMatch, "From: Any"); snap("history-from-date", after: 0.8)
        tap(app.buttons["Hide date range"].firstMatch, "hide dates"); snap("history-filter-hidden", after: 0.8)
        tap(app.staticTexts["FBEOD"].exists ? app.staticTexts["FBEOD"].firstMatch : app.staticTexts["Full body"].firstMatch, "a workout")
        snap("detail", after: 1); app.swipeUp(); snap("detail-large", after: 0.8)
        tap(app.buttons["Close"].firstMatch, "close detail"); snap("history-again", after: 0.8)
        app.swipeUp(); snap("history-scrolled"); app.swipeDown()

        // Settings.
        tap(app.buttons["Settings"].firstMatch, "Settings"); snap("settings", after: 0.8)
        for tab in ["Data", "Account", "About", "Training"] { tap(app.buttons[tab].firstMatch, tab); snap("settings-\(tab)", after: 0.5) }
        tap(app.buttons["System"].firstMatch, "appearance menu"); tap(app.buttons["Light"].firstMatch, "Light")
        snap("settings-light", after: 0.8)
        tap(app.buttons["Light"].firstMatch, "appearance menu"); tap(app.buttons["Dark"].firstMatch, "Dark")
        tap(app.buttons["Close"].firstMatch, "close settings")

        // A new split.
        tap(app.tabBars.buttons["Home"], "Home")
        tap(app.buttons["Create split"].firstMatch, "Create split"); snap("create-split", after: 0.8)
        app.typeText("Legs"); tap(app.buttons["dialog-action"], "create"); snap("split-page", after: 1)
        tap(app.buttons["Add exercise"].firstMatch, "Add exercise"); snap("library", after: 1)
        tap(app.textFields["Search exercises…"], "search"); app.typeText("squat"); snap("library-search", after: 0.6)
        tap(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Add '")).firstMatch, "add an exercise"); snap("split-with-exercise", after: 0.8)
        tap(app.navigationBars.buttons.firstMatch, "back"); snap("home-new-split", after: 0.8)
        let row = app.cells.containing(.staticText, identifier: "Legs").firstMatch
        if row.waitForExistence(timeout: 3) { row.swipeLeft(); snap("split-swiped", after: 0.5) }
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
        let kg = app.textFields["Bench Press set 1 weight in lb"]
        tap(kg, "lb field"); app.typeText("135"); app.textFields["Bench Press set 1 reps"].tap(); app.typeText("10")
        app.textFields["Bench Press set 1 RIR"].tap(); app.typeText("2"); snap("manual-typed-not-logged", after: 1)
        tap(check("Bench Press set 1"), "✓ set 1"); snap("manual-ticked", after: 0.8)
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
        if element.waitForExistence(timeout: 4), element.isHittable { element.tap() } else { print("TOUR missing: \(what) (step \(step))") }
    }

    private func check(_ set: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", set + ":")).firstMatch
    }
}
