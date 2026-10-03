import Foundation
import UserNotifications

/// The rest timer's end as a notification, so it reaches you with Track in the background or the phone locked.
/// In the app itself the capsule's haptic says it instead (notifications don't show while Track is open).
enum RestAlert {
    private static let id = "track.rest"

    /// Asks once, the first time a rest starts.
    static func schedule(at until: Int) {
        guard ScreenshotMode.screen == nil else { return } // the permission prompt would cover the screenshots
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
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
