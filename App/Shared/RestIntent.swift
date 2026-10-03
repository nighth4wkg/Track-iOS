import AppIntents

/// +30s and Skip on the rest timer's Live Activity. Being a Live Activity intent, it runs in Track itself (woken in
/// the background if needed), which changes the rest; the widget extension only draws the buttons.
struct RestIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Change rest"
    static let isDiscoverable = false

    /// Seconds to add; 0 ends the rest.
    @Parameter(title: "Seconds") var seconds: Int

    init() {}
    init(seconds: Int) { self.seconds = seconds }

    /// Set by the app at launch.
    nonisolated(unsafe) static var change: ((Int) async -> Void)?

    func perform() async throws -> some IntentResult {
        await Self.change?(seconds)
        return .result()
    }
}
