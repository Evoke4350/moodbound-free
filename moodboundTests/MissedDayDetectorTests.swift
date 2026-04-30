import XCTest
@testable import moodbound

final class MissedDayDetectorTests: XCTestCase {
    private struct Fixture: DateRepresenting {
        let dateValue: Date
    }

    private var calendar: Calendar { .current }

    private func day(_ year: Int, _ month: Int, _ d: Int, hour: Int = 12) -> Date {
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = d
        comps.hour = hour
        return calendar.date(from: comps)!
    }

    func testNoGapWhenLoggedToday() {
        let now = day(2026, 4, 29, hour: 18)
        let entries = [Fixture(dateValue: day(2026, 4, 29, hour: 9))]
        let result = MissedDayDetector.recommend(entries: entries, now: now)
        XCTAssertEqual(result, .noGap)
    }

    func testBackfillForOneToThreeMissedDays() {
        let now = day(2026, 4, 28, hour: 18)
        let entries = [Fixture(dateValue: day(2026, 4, 25, hour: 10))]
        let result = MissedDayDetector.recommend(entries: entries, now: now)
        if case .backfill(let missing) = result {
            // 26, 27, 28 — 25 is logged, 28 is today and missing
            XCTAssertEqual(missing.count, 3)
        } else {
            XCTFail("Expected backfill, got \(result)")
        }
    }

    func testBackfillIncludesTodayWhenNotLogged() {
        let now = day(2026, 4, 29, hour: 18)
        let entries = [Fixture(dateValue: day(2026, 4, 27, hour: 10))]
        let result = MissedDayDetector.recommend(entries: entries, now: now)
        if case .backfill(let missing) = result {
            // 28 + 29 = 2 days
            XCTAssertEqual(missing.count, 2)
            XCTAssertTrue(missing.contains(calendar.startOfDay(for: now)))
        } else {
            XCTFail("Expected backfill, got \(result)")
        }
    }

    func testReminderOptInWhenMoreThanThreeDaysMissed() {
        let now = day(2026, 4, 29, hour: 18)
        let entries = [Fixture(dateValue: day(2026, 4, 22, hour: 10))]
        let result = MissedDayDetector.recommend(entries: entries, now: now)
        if case .offerReminders(let count) = result {
            XCTAssertEqual(count, 7) // 23..29
        } else {
            XCTFail("Expected offerReminders, got \(result)")
        }
    }

    func testMultipleEntriesSameDayCountAsLogged() {
        let now = day(2026, 4, 29, hour: 18)
        let entries = [
            Fixture(dateValue: day(2026, 4, 29, hour: 9)),
            Fixture(dateValue: day(2026, 4, 29, hour: 18)),
            Fixture(dateValue: day(2026, 4, 28, hour: 10)),
        ]
        let result = MissedDayDetector.recommend(entries: entries, now: now)
        XCTAssertEqual(result, .noGap)
    }

    func testRecommendationEqualityWorks() {
        let now = day(2026, 4, 29)
        let entries = [Fixture(dateValue: day(2026, 4, 27))]
        let a = MissedDayDetector.recommend(entries: entries, now: now)
        let b = MissedDayDetector.recommend(entries: entries, now: now)
        XCTAssertEqual(a, b)
    }
}

final class ReminderSettingsTimesTests: XCTestCase {
    func testAllTimesSortedAndDeduplicated() {
        let settings = ReminderSettings(
            enabled: true,
            hour: 20,
            minute: 0,
            additionalMinutes: [60 * 13, 60 * 20] // 1 PM, 8 PM (8 PM duplicates primary)
        )
        let times = settings.allTimes
        XCTAssertEqual(times.count, 2)
        XCTAssertEqual(times[0].hour, 13)
        XCTAssertEqual(times[1].hour, 20)
    }

    func testClampMinutesGuardsOutOfRange() {
        XCTAssertEqual(ReminderSettings.clampMinutes(-100), 0)
        XCTAssertEqual(ReminderSettings.clampMinutes(99_999), 1439)
        XCTAssertEqual(ReminderSettings.clampMinutes(720), 720)
    }

    func testEmptyAdditionalReturnsSinglePrimary() {
        let settings = ReminderSettings(enabled: true, hour: 8, minute: 30)
        let times = settings.allTimes
        XCTAssertEqual(times.count, 1)
        XCTAssertEqual(times[0].hour, 8)
        XCTAssertEqual(times[0].minute, 30)
    }
}
