import XCTest

/// Track iOS driven like a person would, in the Simulator (.github/workflows/uitests.yml): each test starts from the
/// demo training (TRACK_SEED) on this iPhone only, taps through one flow, and keeps a screenshot of where it ended.
final class TrackUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-track.storageMode", "local"]
        app.launchEnvironment["TRACK_SEED"] = ProcessInfo.processInfo.environment["TRACK_SEED"]
        app.launch()
    }

    override func tearDown() {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    /// Start the next split, log a set by typing it, add a set (it copies weight and reps, not RIR), delete it with
    /// the swipe and bring it back, then finish: the recap, then Progress.
    func testWorkoutFromStartToRecap() {
        app.buttons["Start workout"].firstMatch.tapWhenReady()
        let weight = app.textFields["Bench Press set 1 weight in kg"]
        weight.replaceText("80")
        app.textFields["Bench Press set 1 reps"].replaceText("8")
        XCTAssertFalse(setButton("Bench Press set 1", done: true).exists, "logged before RIR")
        app.textFields["Bench Press set 1 RIR"].replaceText("1")
        XCTAssertTrue(setButton("Bench Press set 1", done: true).waitForExistence(timeout: 3), "typing RIR logs the set")
        allowNotificationsIfAsked()

        app.buttons["Add set"].firstMatch.tapWhenReady()
        let added = app.textFields["Bench Press set 4 weight in kg"]
        XCTAssertTrue(added.waitForExistence(timeout: 3))
        XCTAssertEqual(added.value as? String, "77.5", "a new set copies the last weight")
        XCTAssertEqual(app.textFields["Bench Press set 4 reps"].value as? String, "8")
        XCTAssertNotEqual(app.textFields["Bench Press set 4 RIR"].value as? String, "2", "RIR is left to fill in")

        app.textFields["Bench Press set 4 RIR"].swipeLeft()
        app.buttons["Delete Bench Press set 4"].tapWhenReady()
        XCTAssertTrue(app.descendants(matching: .any)["Set removed"].waitForExistence(timeout: 3))
        app.buttons["Undo"].tapWhenReady()
        XCTAssertTrue(app.textFields["Bench Press set 4 weight in kg"].waitForExistence(timeout: 3), "Undo brings the set back")

        app.buttons["Finish workout"].firstMatch.tapWhenReady()
        app.buttons["dialog-action"].tapWhenReady()
        XCTAssertTrue(app.staticTexts["Nice workout!"].waitForExistence(timeout: 5))
        app.buttons["Continue"].tapWhenReady()
        XCTAssertTrue(app.tabBars.buttons["Progress"].waitForSelected(), "Continue goes to Progress")
    }

    /// Create a split, add an exercise from the library, go back Home, swipe the split away and confirm.
    func testCreateAndDeleteASplit() {
        app.buttons["Create split"].firstMatch.tapWhenReady()
        let name = app.textFields["e.g. Upper body"]
        XCTAssertTrue(name.waitForExistence(timeout: 3))
        name.typeText("Arms day")
        dismissKeyboardTip()
        app.buttons["dialog-action"].tapWhenReady()
        XCTAssertTrue(app.staticTexts["Tap to add exercises"].waitForExistence(timeout: 5), "the new split's page opens")

        app.buttons["Add exercise"].firstMatch.tapWhenReady()
        app.textFields["Search exercises…"].tapWhenReady()
        app.textFields["Search exercises…"].typeText("Barbell curl")
        dismissKeyboardTip()
        app.buttons["Add Barbell curl"].firstMatch.tapWhenReady()
        XCTAssertTrue(app.staticTexts["Barbell curl"].waitForExistence(timeout: 3))

        app.navigationBars.buttons.firstMatch.tapWhenReady()
        let row = app.cells.containing(.staticText, identifier: "Arms day").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 3))
        row.swipeLeft()
        XCTAssertTrue(app.tabBars.buttons["Home"].isSelected, "a row's swipe isn't a tab swipe")
        app.buttons["Delete"].firstMatch.tapWhenReady()
        app.buttons["dialog-action"].tapWhenReady()
        XCTAssertTrue(row.waitForNonExistence(timeout: 3), "the split is gone")
    }

    /// History: open a workout, add to its note and save it; then swipe between tabs.
    func testHistoryDetailNoteAndTabSwipe() {
        app.tabBars.buttons["History"].tapWhenReady()
        app.staticTexts["Full body"].firstMatch.tapWhenReady()
        app.buttons["Add a note"].firstMatch.tapWhenReady()
        let note = app.textViews.firstMatch.exists ? app.textViews.firstMatch : app.textFields["How did this workout feel?"]
        note.tapWhenReady()
        note.typeText("Good pump")
        app.buttons["Save note"].tapWhenReady()
        XCTAssertTrue(app.staticTexts["Good pump"].waitForExistence(timeout: 3), "the note shows")
        app.buttons["Close"].firstMatch.tapWhenReady()

        swipePage(left: true)
        XCTAssertTrue(app.tabBars.buttons["Progress"].waitForSelected(), "swiping left goes to the next tab")
        swipePage(left: false)
        XCTAssertTrue(app.tabBars.buttons["History"].waitForSelected(), "swiping right comes back")
    }

    /// Settings: every tab opens, and switching to pounds shows on Home.
    func testSettingsTabsAndUnit() {
        app.buttons["Settings"].firstMatch.tapWhenReady()
        for tab in ["Data", "Account", "About", "Training"] { app.buttons[tab].firstMatch.tapWhenReady() }
        app.buttons["kg"].firstMatch.tapWhenReady()
        app.buttons["lb"].firstMatch.tapWhenReady()
        app.buttons["Close"].firstMatch.tapWhenReady()
        XCTAssertTrue(app.staticTexts["lb"].firstMatch.waitForExistence(timeout: 3), "Home shows pounds")
    }

    /// A sideways swipe across the page's upper part (the title area), away from the screen's edges.
    private func swipePage(left: Bool) {
        let window = app.windows.firstMatch
        let from = window.coordinate(withNormalizedOffset: CGVector(dx: left ? 0.8 : 0.2, dy: 0.16))
        let to = window.coordinate(withNormalizedOffset: CGVector(dx: left ? 0.2 : 0.8, dy: 0.16))
        from.press(forDuration: 0.05, thenDragTo: to, withVelocity: .fast, thenHoldForDuration: 0)
    }

    /// The first rest asks to send notifications (the system's alert, outside the app).
    private func allowNotificationsIfAsked() {
        let allow = XCUIApplication(bundleIdentifier: "com.apple.springboard").buttons["Allow"]
        if allow.waitForExistence(timeout: 3) { allow.tap() }
    }

    /// The Simulator's one-time "slide to type" tip over the keyboard.
    private func dismissKeyboardTip() {
        let tip = app.buttons["Continue"]
        if tip.waitForExistence(timeout: 1) { tip.tap() }
    }

    private func setButton(_ set: String, done: Bool) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@ AND label CONTAINS %@", set, done ? "done. Tap to undo" : "")).firstMatch
    }
}

extension XCUIElement {
    func tapWhenReady(file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(waitForExistence(timeout: 5), "missing: \(self)", file: file, line: line)
        tap()
    }

    /// Taps the field and types over what's in it.
    func replaceText(_ text: String, file: StaticString = #filePath, line: UInt = #line) {
        tapWhenReady(file: file, line: line)
        let current = (value as? String) ?? ""
        if !current.isEmpty, current != placeholderValue { typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count + 2)) }
        typeText(text)
    }

    func waitForSelected(timeout: TimeInterval = 3) -> Bool {
        let end = Date().addingTimeInterval(timeout)
        while Date() < end { if isSelected { return true }; RunLoop.current.run(until: Date().addingTimeInterval(0.1)) }
        return isSelected
    }
}
