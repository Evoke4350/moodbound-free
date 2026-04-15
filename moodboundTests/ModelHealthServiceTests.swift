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
}
