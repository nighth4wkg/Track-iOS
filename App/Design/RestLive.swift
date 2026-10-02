import ActivityKit
import Foundation

/// Starts, moves and ends the rest timer's Live Activity, so the countdown shows in the Dynamic Island and on the
/// Lock Screen while you're out of Track. One at a time.
enum RestLive {
    static func show(until: Int, seconds: Int, workout: String) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let end = Date(timeIntervalSince1970: Double(until) / 1000)
        let state = RestAttributes.ContentState(until: end, seconds: seconds)
        let content = ActivityContent(state: state, staleDate: end)
        if let current = Activity<RestAttributes>.activities.first {
            Task { await current.update(content) }
        } else {
            _ = try? Activity.request(attributes: RestAttributes(workout: workout), content: content)
        }
    }

    static func end() {
        for activity in Activity<RestAttributes>.activities {
            Task { await activity.end(nil, dismissalPolicy: .immediate) }
        }
    }
}
