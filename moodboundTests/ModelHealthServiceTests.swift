import XCTest
@testable import moodbound

final class ModelHealthServiceTests: XCTestCase {
    func testDriftAndStaleDataCanDegradeHealth() {
        let entries = RealisticMoodDatasetFactory.makeScenario(days: 140).entries
        for entry in entries.suffix(14) {
            entry.moodLevel = 3
            entry.sleepHours = 4.2
            entry.energy = 5
        }
        let vectors = FeatureStoreService.buildVectors(entries: entries)
        let forecast = ProbabilisticScore(value: 0.62, ciLow: 0.4, ciHigh: 0.85, calibrationError: 0.31)
        let now = entries.last!.timestamp.addingTimeInterval(20 * 86_400)

        let status = ModelHealthService.assess(vectors: vectors, forecast: forecast, now: now)
        XCTAssertEqual(status.level, .degraded)
        XCTAssertGreaterThan(status.driftScore, 0.35)
        XCTAssertFalse(status.alerts.isEmpty)
    }

    func testHealthyStatusWhenStableAndFresh() {
        let entries = Array(RealisticMoodDatasetFactory.makeScenario(days: 60).entries[0..<30])
        let vectors = FeatureStoreService.buildVectors(entries: entries)
        let forecast = ProbabilisticScore(value: 0.22, ciLow: 0.15, ciHigh: 0.3, calibrationError: 0.06)
        let now = entries.last!.timestamp.addingTimeInterval(1 * 86_400)

        let status = ModelHealthService.assess(vectors: vectors, forecast: forecast, now: now)
        XCTAssertEqual(status.level, .healthy)
        XCTAssertLessThan(status.driftScore, 0.35)
    }

    // Regression: staleDays previously used `now.timeIntervalSince(latest) / 86_400`,
    // which counts 24-hour deltas, not calendar boundaries. An entry logged
    // yesterday at 8pm against a "now" of 6am today is 10 hours old (= 0 days
    // by raw delta) but is clearly 1 calendar day stale — the user missed a day.
    func testStaleDaysCountsCalendarBoundaryNotRawHours() {
        let calendar = Calendar.current
        let yesterdayEvening = calendar.date(from: DateComponents(year: 2026, month: 4, day: 19, hour: 20, minute: 0))!
        let thisMorning = calendar.date(from: DateComponents(year: 2026, month: 4, day: 20, hour: 6, minute: 0))!

        let vector = TemporalFeatureVector(
            timestamp: yesterdayEvening,
            moodLevel: 0,
            sleepHours: 7,
            energy: 3,
            anxiety: 0,
            irritability: 0,
            medAdherenceRate7d: nil,
            triggerLoad7d: nil,
            volatility7d: nil,
            circadianDrift7d: nil
        )
        let forecast = ProbabilisticScore(value: 0.2, ciLow: 0.1, ciHigh: 0.3, calibrationError: 0.05)
        let status = ModelHealthService.assess(vectors: [vector], forecast: forecast, now: thisMorning)
        XCTAssertEqual(status.staleDays, 1)
    }
}
