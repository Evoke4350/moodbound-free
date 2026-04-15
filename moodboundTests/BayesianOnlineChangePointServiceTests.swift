import XCTest
@testable import moodbound

final class BayesianOnlineChangePointServiceTests: XCTestCase {
    func testBOCPDRaisesChangeProbabilityOnAbruptShift() {
        let entries = RealisticMoodDatasetFactory.makeScenario(days: 150).entries
        let vectors = FeatureStoreService.buildVectors(entries: entries)

        let result = BayesianOnlineChangePointService.detect(vectors: vectors)
        XCTAssertEqual(result.points.count, vectors.count)
        XCTAssertGreaterThan(result.latestChangeProbability, 0.1)

        let stableWindowMax = result.points[84..<110].map(\.changeProbability).max() ?? 0
        let activationOnsetMax = result.points[112..<126].map(\.changeProbability).max() ?? 0
        XCTAssertGreaterThan(activationOnsetMax, stableWindowMax)
    }
}
