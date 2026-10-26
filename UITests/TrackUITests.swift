import XCTest

// Helpers the UI tests share (TrackTour, ScrollProfile). The old app's flow tests here were retired with the recode:
// TrackTour covers its screens.

/// The first rest asks to send notifications (the system's alert, outside the app).
func allowNotificationsIfAsked() {
    let allow = XCUIApplication(bundleIdentifier: "com.apple.springboard").buttons["Allow"]
    if allow.waitForExistence(timeout: 3) { allow.tap() }
}

extension XCUIApplication {
    /// Types on the keyboard's keys: a set's fields are typed on the workout's one keyboard, not a text field of their own.
    func typeKeys(_ text: String) { for key in text { keys[String(key)].tap() } }
}

extension XCUIElement {
    func tapWhenReady(file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(waitForExistence(timeout: 5), "missing: \(self)", file: file, line: line)
        tap()
    }

    /// Taps a set's field and types over what's in it (its first key replaces it).
    func replaceText(_ text: String, file: StaticString = #filePath, line: UInt = #line) {
        tapWhenReady(file: file, line: line)
        XCUIApplication().typeKeys(text)
    }

    func waitForSelected(timeout: TimeInterval = 3) -> Bool {
        let end = Date().addingTimeInterval(timeout)
        while Date() < end { if isSelected { return true }; RunLoop.current.run(until: Date().addingTimeInterval(0.1)) }
        return isSelected
    }
}
