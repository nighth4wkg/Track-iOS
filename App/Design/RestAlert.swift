import Foundation
import UserNotifications

/// The rest timer's end as a notification, so it reaches you with Track in the background or the phone locked.
/// In the app itself the capsule's haptic says it instead (notifications don't show while Track is open).
enum RestAlert {
    private static let id = "track.rest"

    /// Schedules the alert. The very first rest asks whether Track may notify (iOS asks only once, ever), so the
    /// question comes when its point is plain, not over the workout as it opens.
    static func schedule(at until: Int) {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            if settings.authorizationStatus == .notDetermined {
                guard ScreenshotMode.screen == nil else { return } // the prompt would cover the screenshots
                center.requestAuthorization(options: [.alert, .sound]) { granted, _ in if granted { schedule(at: until) } }
                return
            }
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
