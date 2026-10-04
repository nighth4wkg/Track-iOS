import Foundation
import UserNotifications

/// The rest timer's end as a notification, so it reaches you with Track in the background or the phone locked.
/// In the app itself the capsule's haptic says it instead (notifications don't show while Track is open).
enum RestAlert {
    private static let id = "track.rest"

    /// Asks once, as a workout starts (a calm moment), never while you're logging a set. A question left unanswered
    /// is asked again only at the next workout.
    static func prepare() {
        guard ScreenshotMode.screen == nil else { return } // the prompt would cover the screenshots
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .notDetermined else { return }
            center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
        }
    }

    /// Schedules the alert when notifications are allowed; otherwise does nothing (no prompt mid-workout).
    static func schedule(at until: Int) {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            guard [.authorized, .provisional, .ephemeral].contains(settings.authorizationStatus) else { return }
            let content = UNMutableNotificationContent()
            content.title = "Rest’s up"
            content.body = "Time for your next set."
            content.sound = .default
            content.interruptionLevel = .timeSensitive
            let seconds = max(1, Double(until) / 1000 - Date.now.timeIntervalSince1970)
            let request = UNNotificationRequest(identifier: id, content: content,
                                                trigger: UNTimeIntervalNotificationTrigger(timeInterval: seconds, repeats: false))
            center.removePendingNotificationRequests(withIdentifiers: [id])
            center.add(request)
        }
    }

    static func cancel() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id])
    }
}
