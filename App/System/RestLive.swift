import ActivityKit
import UIKit

/// Starts, moves and ends the rest timer's Live Activity, so the countdown shows in the Dynamic Island and on the
/// Lock Screen while you're out of Track. One for the whole workout: between rests it says "Ready", so iOS isn't
/// asked to start (and confirm) a new one every set; it ends with the workout.
enum RestLive {
    /// The last change, for a Live Activity button to wait on before Track goes back to sleep.
    nonisolated(unsafe) private(set) static var pending: Task<Void, Never>?

    static func show(until: Int, seconds: Int, workout: String) {
        after {
            guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
            let end = Date(timeIntervalSince1970: Double(until) / 1000)
            let content = ActivityContent(state: RestAttributes.ContentState(until: end, seconds: seconds), staleDate: end)
            let current = live
            if current.isEmpty {
                _ = try? Activity.request(attributes: RestAttributes(workout: workout), content: content)
            } else {
                for activity in current { await activity.update(content) }
            }
        }
    }

    /// Between rests: the same activity, now "Ready for your next set" (nothing to start if there's none).
    static func idle() {
        after {
            let content = ActivityContent(state: RestAttributes.ContentState(until: .now, seconds: 1, resting: false), staleDate: nil)
            for activity in live { await activity.update(content) }
        }
    }

    /// Track's activities still showing (a rest that ran out is stale, not over); every one is kept in step, so one
    /// left behind can't go on showing an old rest.
    private static var live: [Activity<RestAttributes>] {
        Activity<RestAttributes>.activities.filter { $0.activityState == .active || $0.activityState == .stale }
    }

    /// Says "Ready" as the rest runs out, while Track is running: the activity's stale date alone left "Rest 0:00" up
    /// on the iPhone. iOS's few seconds of background time cover a rest ending just after leaving Track; coming back
    /// to Track catches a later one (Shell).
    @MainActor static func readyWhenOver(_ until: Int?) async {
        guard let until else { return }
        let wait = Double(until) / 1000 - Date.now.timeIntervalSince1970
        guard wait > 0 else { return }
        var token = UIBackgroundTaskIdentifier.invalid
        token = UIApplication.shared.beginBackgroundTask { UIApplication.shared.endBackgroundTask(token); token = .invalid }
        defer { if token != .invalid { UIApplication.shared.endBackgroundTask(token) } }
        try? await Task.sleep(for: .seconds(wait))
        if !Task.isCancelled { idle() }
    }

    static func end() {
        after { for activity in Activity<RestAttributes>.activities { await activity.end(nil, dismissalPolicy: .immediate) } }
    }

    /// Runs `work` off the main thread (asking ActivityKit cost a workout's start ~15 ms of frames there), once the
    /// change before it is done, so changes land in order. Called on the main thread only: `pending` is set at once,
    /// so a Live Activity button waiting on it waits for this too.
    private static func after(_ work: @escaping @Sendable () async -> Void) {
        let previous = pending
        pending = Task.detached(priority: .userInitiated) {
            await previous?.value
            await work()
        }
    }
}
