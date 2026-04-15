import XCTest
@testable import moodbound

final class ChangePointServiceTests: XCTestCase {
    func testDetectsUpwardRegimeShift() {
        let entries = RealisticMoodDatasetFactory.makeScenario(days: 150).entries
        let vectors = FeatureStoreService.buildVectors(entries: entries)
        let activationStart = vectors[112].timestamp

        let events = ChangePointService.detect(vectors: vectors)
        XCTAssertTrue(events.contains { $0.direction == .upward && $0.timestamp >= activationStart })
    }

    func testDetectsDownwardRegimeShift() {
        let entries = RealisticMoodDatasetFactory.makeScenario(days: 150).entries
        let vectors = FeatureStoreService.buildVectors(entries: entries)
        let depressiveStart = vectors[42].timestamp
        let upperBound = vectors[95].timestamp

        let events = ChangePointService.detect(vectors: vectors)
        XCTAssertTrue(events.contains {
            $0.direction == .downward &&
            $0.timestamp >= depressiveStart &&
            $0.timestamp <= upperBound
        })
    }

    func testNoFalsePositiveOnStationarySeries() {
        let entries = RealisticMoodDatasetFactory.makeScenario(days: 30).entries
        let vectors = entries.map { entry in
            TemporalFeatureVector(
                timestamp: entry.timestamp,
                moodLevel: 0.08,
                sleepHours: 7.25,
                energy: 3.05,
                anxiety: 1.1,
                irritability: 1.0,
                medAdherenceRate7d: 0.9,
                triggerLoad7d: 1.0,
                volatility7d: 0.25,
                circadianDrift7d: 0.2
            )
        }

        let events = ChangePointService.detect(vectors: vectors)
        XCTAssertTrue(events.isEmpty)
    }
}
