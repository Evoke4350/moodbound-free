import Foundation
import SwiftData

@Model
final class ReminderSettings {
    var enabled: Bool
    var hour: Int
    var minute: Int
    var message: String
    var updatedAt: Date

    init(
        enabled: Bool = false,
        hour: Int = 20,
        minute: Int = 0,
        message: String = NSLocalizedString("reminder.default_message", comment: ""),
        updatedAt: Date = .now
    ) {
        self.enabled = enabled
        self.hour = hour
        self.minute = minute
        self.message = message
        self.updatedAt = updatedAt
    }
}
