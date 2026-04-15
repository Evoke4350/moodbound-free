import Foundation
import UserNotifications

enum ReminderSchedulerError: LocalizedError {
    case notificationsDenied

    var errorDescription: String? {
        switch self {
        case .notificationsDenied:
            return "Notifications are disabled for moodbound. Enable them in Settings to use reminders."
        }
    }
}

enum ReminderScheduler {
    static let requestIdentifier = "moodbound.daily.checkin.reminder"

    static func sync(with settings: ReminderSettings) async throws {
        let center = UNUserNotificationCenter.current()
        if !settings.enabled {
            center.removePendingNotificationRequests(withIdentifiers: [requestIdentifier])
            return
        }

        let granted = try await requestAuthorizationIfNeeded(center: center)
        guard granted else {
            throw ReminderSchedulerError.notificationsDenied
        }

        let content = UNMutableNotificationContent()
        content.title = L10n.tr("reminder.title")
        content.body = settings.message
        content.sound = .default

        var dateComponents = DateComponents()
        dateComponents.hour = settings.hour
        dateComponents.minute = settings.minute

        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
        let request = UNNotificationRequest(
            identifier: requestIdentifier,
            content: content,
            trigger: trigger
        )

        center.removePendingNotificationRequests(withIdentifiers: [requestIdentifier])
        try await center.add(request)
    }

    private static func requestAuthorizationIfNeeded(center: UNUserNotificationCenter) async throws -> Bool {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .notDetermined:
            return try await center.requestAuthorization(options: [.alert, .badge, .sound])
        case .denied:
            return false
        @unknown default:
            return false
        }
    }
}
