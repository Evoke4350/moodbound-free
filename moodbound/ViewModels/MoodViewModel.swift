import Foundation
import SwiftData

@Observable
class MoodViewModel {

    func streakDays(entries: [MoodEntry], now: Date = AppClock.now) -> Int {
        let calendar = Calendar.current
        let sorted = entries.sorted { $0.timestamp > $1.timestamp }
        guard let first = sorted.first,
              calendar.isDate(first.timestamp, inSameDayAs: now) else { return 0 }

        var streak = 1
        var previousDay = calendar.startOfDay(for: first.timestamp)

        for entry in sorted.dropFirst() {
            let entryDay = calendar.startOfDay(for: entry.timestamp)
            if entryDay == previousDay { continue }
            let diff = calendar.dateComponents([.day], from: entryDay, to: previousDay).day ?? 0
            if diff == 1 {
                streak += 1
                previousDay = entryDay
            } else {
                break
            }
        }
        return streak
    }

    func averageMood(entries: [MoodEntry], days: Int, now: Date = AppClock.now) -> Double? {
        let recent = entriesWithinDays(entries: entries, days: days, now: now)
        guard !recent.isEmpty else { return nil }
        return Double(recent.reduce(0) { $0 + $1.moodLevel }) / Double(recent.count)
    }

    func hasLoggedToday(entries: [MoodEntry], now: Date = AppClock.now) -> Bool {
        entries.contains { Calendar.current.isDate($0.timestamp, inSameDayAs: now) }
    }

    func entriesWithinDays(entries: [MoodEntry], days: Int, now: Date = AppClock.now) -> [MoodEntry] {
        // Anchor to start-of-day so a "last 7 days" filter at 9am still
        // includes entries from the morning of day -7. Subtracting raw 24-hour
        // intervals from the wall-clock `now` would silently drop those.
        let calendar = Calendar.current
        let startToday = calendar.startOfDay(for: now)
        let cutoff = calendar.date(byAdding: .day, value: -(days - 1), to: startToday) ?? startToday
        return entries.filter { $0.timestamp >= cutoff }
    }
}
