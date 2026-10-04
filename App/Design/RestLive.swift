import ActivityKit
import Foundation

/// Starts, moves and ends the rest timer's Live Activity, so the countdown shows in the Dynamic Island and on the
/// Lock Screen while you're out of Track. One for the whole workout: between rests it says "Ready", so iOS isn't
/// asked to start (and confirm) a new one every set; it ends with the workout.
enum RestLive {
    /// The last change, for a Live Activity button to wait on before Track goes back to sleep.
    nonisolated(unsafe) private(set) static var pending: Task<Void, Never>?

    static func show(until: Int, seconds: Int, workout: String) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let end = Date(timeIntervalSince1970: Double(until) / 1000)
        let state = RestAttributes.ContentState(until: end, seconds: seconds)
        let content = ActivityContent(state: state, staleDate: end)
        if let current = Activity<RestAttributes>.activities.first {
            pending = Task { await current.update(content) }
        } else {
            _ = try? Activity.request(attributes: RestAttributes(workout: workout), content: content)
        }
    }

    /// Between rests: the same activity, now "Ready for your next set" (nothing to start if there's none).
    static func idle() {
        guard let current = Activity<RestAttributes>.activities.first else { return }
        let state = RestAttributes.ContentState(until: .now, seconds: 1, resting: false)
        pending = Task { await current.update(ActivityContent(state: state, staleDate: nil)) }
    }

    static func end() {
        let activities = Activity<RestAttributes>.activities
        pending = Task { for activity in activities { await activity.end(nil, dismissalPolicy: .immediate) } }
    }
}
