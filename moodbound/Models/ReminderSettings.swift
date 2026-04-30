import Foundation
import SwiftData

@Model
final class ReminderSettings {
    var enabled: Bool
    /// Primary reminder time (legacy single-time field; still the slot-0 time).
    var hour: Int
    var minute: Int
    var message: String
    var updatedAt: Date
    /// Extra reminder times beyond the primary, encoded as minutes-since-midnight (0..1439).
    /// Lazily added in this build for multi-time backfill opt-in; older records
    /// keep working with an empty list.
    var additionalMinutes: [Int] = []

    init(
        enabled: Bool = false,
        hour: Int = 20,
        minute: Int = 0,
        message: String = NSLocalizedString("reminder.default_message", comment: ""),
        updatedAt: Date = .now,
        additionalMinutes: [Int] = []
    ) {
        self.enabled = enabled
        self.hour = hour
        self.minute = minute
        self.message = message
        self.updatedAt = updatedAt
        self.additionalMinutes = additionalMinutes
    }

    /// All scheduled times of day (primary + additional), normalized and sorted.
    /// Each tuple is (hour 0..23, minute 0..59).
    var allTimes: [(hour: Int, minute: Int)] {
        var seen = Set<Int>()
        var ordered: [Int] = []
        let primary = ReminderSettings.clampMinutes(hour * 60 + minute)
        if seen.insert(primary).inserted { ordered.append(primary) }
        for raw in additionalMinutes {
            let normalized = ReminderSettings.clampMinutes(raw)
            if seen.insert(normalized).inserted { ordered.append(normalized) }
        }
        return ordered.sorted().map { (hour: $0 / 60, minute: $0 % 60) }
    }

    static func clampMinutes(_ value: Int) -> Int {
        max(0, min(1439, value))
    }
}
