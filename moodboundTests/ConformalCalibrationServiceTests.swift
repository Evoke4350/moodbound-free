import XCTest
@testable import moodbound

final class ConformalCalibrationServiceTests: XCTestCase {
    func testConformalizationWidensOrMaintainsInterval() {
        let entries = RealisticMoodDatasetFactory.makeScenario(days: 90).entries
        let vectors = FeatureStoreService.buildVectors(entries: entries)
        let raw = ProbabilisticScore(value: 0.42, ciLow: 0.35, ciHigh: 0.49, calibrationError: 0.2)
        let calibrated = ConformalCalibrationService.conformalize(raw: raw, vectors: vectors)

        XCTAssertGreaterThanOrEqual(calibrated.ciWidth, raw.ciWidth)
        XCTAssertLessThanOrEqual(calibrated.ciLow, calibrated.value)
        XCTAssertGreaterThanOrEqual(calibrated.ciHigh, calibrated.value)
        XCTAssertLessThan(calibrated.calibrationError, raw.calibrationError)
    }
}
