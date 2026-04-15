import XCTest
@testable import moodbound

final class WassersteinDriftServiceTests: XCTestCase {
    func testDetectsDistributionShift() {
        let entries = RealisticMoodDatasetFactory.makeScenario(days: 150).entries
        let vectors = FeatureStoreService.buildVectors(entries: Array(entries[90..<132]))
        let status = WassersteinDriftService.assess(vectors: vectors, threshold: 0.1)
        XCTAssertTrue(status.isDriftDetected)
        XCTAssertGreaterThan(status.score, 0)
    }

    func testNoDriftForStableDistribution() {
        let entries = RealisticMoodDatasetFactory.makeScenario(days: 84).entries
        let vectors = FeatureStoreService.buildVectors(entries: Array(entries[0..<42]))
        let status = WassersteinDriftService.assess(vectors: vectors, threshold: 0.1)
        XCTAssertFalse(status.isDriftDetected)
    }
}
