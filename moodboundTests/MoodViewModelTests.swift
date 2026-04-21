import XCTest
@testable import moodbound

final class MoodViewModelTests: XCTestCase {
    func testStreakDaysCountsConsecutiveDaysIncludingToday() {
        let entries = Array(RealisticMoodDatasetFactory.makeScenario(days: 3).entries)
        let now = entries.last!.timestamp.addingTimeInterval(2 * 3_600)

        let streak = MoodViewModel().streakDays(entries: entries, now: now)
        XCTAssertEqual(streak, 3)
    }

    func testStreakDaysIsZeroWhenNoEntryToday() {
        let entries = Array(RealisticMoodDatasetFactory.makeScenario(days: 2).entries)
        let now = entries.last!.timestamp.addingTimeInterval(26 * 3_600)

        let streak = MoodViewModel().streakDays(entries: entries, now: now)
        XCTAssertEqual(streak, 0)
    }

    func testAverageMoodInWindow() {
        let entries = Array(RealisticMoodDatasetFactory.makeScenario(days: 10).entries.suffix(3))
        let now = entries[2].timestamp
        entries[0].timestamp = now.addingTimeInterval(-4 * 86_400)
        entries[1].timestamp = now.addingTimeInterval(-2 * 86_400)
        entries[0].moodLevel = -2
        entries[1].moodLevel = 0
        entries[2].moodLevel = 2

        let average = MoodViewModel().averageMood(entries: entries, days: 3, now: now)
        XCTAssertNotNil(average)
        XCTAssertEqual(average ?? 0, 1.0, accuracy: 0.0001)
    }

    func testEntriesWithinDaysFiltersCorrectly() {
        let entries = Array(RealisticMoodDatasetFactory.makeScenario(days: 20).entries.suffix(3))
        let now = entries[2].timestamp
        entries[0].timestamp = now.addingTimeInterval(-12 * 86_400)
        entries[1].timestamp = now.addingTimeInterval(-5 * 86_400)

        let filtered = MoodViewModel().entriesWithinDays(entries: entries, days: 7, now: now)
        XCTAssertEqual(filtered.count, 2)
    }

    // Regression: the previous wall-clock filter used `now - days*86_400` as
    // the cutoff, so the inclusion of any entry from day -N depended on the
    // time-of-day at which the filter ran. With now=9am and days=7, an entry
    // at 23:59 of (today-7) was wrongly *included* (it sits after the 9am
    // cutoff seven days back), and an entry at 8am of (today-7) — i.e., the
    // morning of the same boundary day — was wrongly *dropped* by an earlier
    // call at 7am the next day. Anchoring to startOfDay makes the cutoff
    // calendar-day-aligned (midnight of today - (days-1)), so both mornings
    // and evenings of the boundary day are treated consistently.
    func testEntriesWithinDaysHonorsCalendarDayBoundary() {
        let calendar = Calendar.current
        let now = calendar.date(from: DateComponents(year: 2026, month: 4, day: 20, hour: 9, minute: 0))!
        let startToday = calendar.startOfDay(for: now)

        let morningOfDayMinus6 = calendar.date(byAdding: .day, value: -6, to: startToday)!
            .addingTimeInterval(8 * 3_600)
        let endOfDayMinus6 = calendar.date(byAdding: .day, value: -6, to: startToday)!
            .addingTimeInterval((23 * 3_600) + (59 * 60))
        let endOfDayMinus7 = calendar.date(byAdding: .day, value: -7, to: startToday)!
            .addingTimeInterval((23 * 3_600) + (59 * 60))

        let morningInside = MoodEntry(timestamp: morningOfDayMinus6, moodLevel: 0, energy: 3, sleepHours: 7, irritability: 0, anxiety: 0, note: "")
        let eveningInside = MoodEntry(timestamp: endOfDayMinus6, moodLevel: 0, energy: 3, sleepHours: 7, irritability: 0, anxiety: 0, note: "")
        let outside = MoodEntry(timestamp: endOfDayMinus7, moodLevel: 0, energy: 3, sleepHours: 7, irritability: 0, anxiety: 0, note: "")

        let filtered = MoodViewModel().entriesWithinDays(entries: [morningInside, eveningInside, outside], days: 7, now: now)
        XCTAssertEqual(filtered.count, 2)
        // Both ends of the boundary day are included regardless of time-of-day.
        XCTAssertTrue(filtered.contains { $0.timestamp == morningOfDayMinus6 })
        XCTAssertTrue(filtered.contains { $0.timestamp == endOfDayMinus6 })
        // The previous calendar day (one day past the 7-day window) is not.
        XCTAssertFalse(filtered.contains { $0.timestamp == endOfDayMinus7 })
    }

    func testValidationRejectsInvalidEnergy() {
        XCTAssertThrowsError(
            try MoodEntryValidator.validate(
                moodLevel: 0,
                energy: 8,
                sleepHours: 8,
                irritability: 0,
                anxiety: 0,
                note: ""
            )
        )
    }

    func testValidationRejectsLongNote() {
        let note = String(repeating: "a", count: MoodEntryValidator.noteLimit + 1)
        XCTAssertThrowsError(
            try MoodEntryValidator.validate(
                moodLevel: 0,
                energy: 3,
                sleepHours: 8,
                irritability: 0,
                anxiety: 0,
                note: note
            )
        )
    }

    func testProperty_StreakAndFilteringInvariantsAcrossRandomizedNow() {
        var rng = ViewModelLCRNG(seed: 0xFACE1234)
        let viewModel = MoodViewModel()
        let calendar = Calendar.current

        for _ in 0..<100 {
            let dayCount = Int.random(in: 5...120, using: &rng)
            let entries = RealisticMoodDatasetFactory.makeScenario(days: dayCount).entries
            let now = entries.last!.timestamp.addingTimeInterval(Double.random(in: -12 * 3_600 ... 36 * 3_600, using: &rng))

            let streak = viewModel.streakDays(entries: entries, now: now)
            let uniqueDays = Set(entries.map { calendar.startOfDay(for: $0.timestamp) }).count
            XCTAssertGreaterThanOrEqual(streak, 0)
            XCTAssertLessThanOrEqual(streak, uniqueDays)

            if !entries.contains(where: { calendar.isDate($0.timestamp, inSameDayAs: now) }) {
                XCTAssertEqual(streak, 0)
            }

            let days = Int.random(in: 1...21, using: &rng)
            let filtered = viewModel.entriesWithinDays(entries: entries, days: days, now: now)
            let cutoff = calendar.date(byAdding: .day, value: -days, to: now) ?? now
            XCTAssertTrue(filtered.allSatisfy { $0.timestamp >= cutoff })
        }
    }
}

private struct ViewModelLCRNG: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        self.state = seed
    }

    mutating func next() -> UInt64 {
        state = 2862933555777941757 &* state &+ 3037000493
        return state
    }
}
