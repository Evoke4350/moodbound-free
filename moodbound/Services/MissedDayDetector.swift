import Foundation

enum MissedDayDetector {
    /// Maximum missed-day count we'll offer to backfill in one batch.
    /// Beyond this we redirect to a reminders opt-in instead — it's not
    /// realistic to ask someone to recall a week of moods at once.
    static let massEntryLimit = 3

    enum Recommendation: Equatable {
        /// User logged today (or no entries yet — handled separately).
        case noGap
        /// Up to `massEntryLimit` calendar days are missing — offer batch entry.
        case backfill(missingDays: [Date])
        /// More than `massEntryLimit` days missing — offer reminders instead.
        case offerReminders(missingCount: Int)
    }

    /// Returns the missing calendar days (start-of-day) between the most
    /// recent entry and `now`, inclusive of today if not logged. Pre-history
    /// (days before the first ever entry) is intentionally excluded — those
    /// aren't "missed", the user simply wasn't using the app yet. Caps at
    /// `lookbackCap` to avoid returning huge lists for users returning after
    /// a long absence.
    static func missingDays(
        entries: [DateRepresenting],
        now: Date,
        lookbackCap: Int = 30,
        calendar: Calendar = .current
    ) -> [Date] {
        let today = calendar.startOfDay(for: now)
        let loggedDays = Set(entries.map { calendar.startOfDay(for: $0.dateValue) })
        guard let mostRecent = loggedDays.max() else { return [] }
        if mostRecent >= today { return [] }
        let dayDiff = calendar.dateComponents([.day], from: mostRecent, to: today).day ?? 0
        // Walk forward from the day after the most recent entry up through today.
        // Cap to keep the offerReminders branch from inflating numbers absurdly.
        var missing: [Date] = []
        let span = min(dayDiff, lookbackCap)
        for offset in 1...max(1, span) {
            guard let day = calendar.date(byAdding: .day, value: offset, to: mostRecent) else { continue }
            if day > today { break }
            if !loggedDays.contains(day) {
                missing.append(day)
            }
        }
        return missing
    }

    /// Recommends what UX to surface for a user who hasn't logged in a while.
    static func recommend(
        entries: [DateRepresenting],
        now: Date,
        lookbackCap: Int = 30,
        calendar: Calendar = .current
    ) -> Recommendation {
        let missing = missingDays(entries: entries, now: now, lookbackCap: lookbackCap, calendar: calendar)
        if missing.isEmpty { return .noGap }
        if missing.count <= massEntryLimit {
            return .backfill(missingDays: missing)
        }
        return .offerReminders(missingCount: missing.count)
    }
}

/// Light protocol so the detector can run against either real `MoodEntry`
/// objects or lightweight test fixtures without dragging SwiftData into
/// pure-logic tests.
protocol DateRepresenting {
    var dateValue: Date { get }
}

extension MoodEntry: DateRepresenting {
    var dateValue: Date { timestamp }
}
