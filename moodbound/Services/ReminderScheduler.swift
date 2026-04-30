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
    static let requestIdentifierPrefix = "moodbound.daily.checkin.reminder"

    static func sync(with settings: ReminderSettings) async throws {
        let center = UNUserNotificationCenter.current()
        await clearAll(center: center)

        if !settings.enabled {
            return
        }

        let granted = try await requestAuthorizationIfNeeded(center: center)
        guard granted else {
            throw ReminderSchedulerError.notificationsDenied
        }

        let times = settings.allTimes
        guard !times.isEmpty else { return }

        for (index, time) in times.enumerated() {
            let content = UNMutableNotificationContent()
            content.title = L10n.tr("reminder.title")
            content.body = settings.message
            content.sound = .default

            var dateComponents = DateComponents()
            dateComponents.hour = time.hour
            dateComponents.minute = time.minute

            let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
            // Slot 0 keeps the legacy identifier so existing pending requests
            // get cleanly replaced; slots 1..n use suffixed identifiers.
            let identifier = index == 0
                ? requestIdentifier
                : "\(requestIdentifierPrefix).\(index)"
            let request = UNNotificationRequest(
                identifier: identifier,
                content: content,
                trigger: trigger
            )
            try await center.add(request)
        }
    }

    /// Removes any pending check-in reminder, including legacy single-slot
    /// and multi-slot identifiers from prior builds. Best-effort: a stale
    /// identifier we never recorded is harmless and gets cleared by iOS
    /// when re-installed.
    static func clearAll(center: UNUserNotificationCenter = .current()) async {
        let pending = await center.pendingNotificationRequests()
        let ids = pending
            .map(\.identifier)
            .filter { $0 == requestIdentifier || $0.hasPrefix("\(requestIdentifierPrefix).") }
        if !ids.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: ids)
        }
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
