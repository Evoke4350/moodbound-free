import XCTest
@testable import moodbound

final class RiskForecastServiceTests: XCTestCase {
    func testForecastOutputBoundsAndOrdering() {
        let scenario = RealisticMoodDatasetFactory.makeScenario(days: 140).entries
        let stable = FeatureStoreService.buildVectors(entries: Array(scenario.prefix(28)))
        let severe = FeatureStoreService.buildVectors(entries: Array(scenario[112..<140]))

        let stableScore = RiskForecastService.forecast7dRisk(vectors: stable)
        let severeScore = RiskForecastService.forecast7dRisk(vectors: severe)

        XCTAssertGreaterThanOrEqual(stableScore.value, 0)
        XCTAssertLessThanOrEqual(stableScore.value, 1)
        XCTAssertGreaterThanOrEqual(stableScore.ciLow, 0)
        XCTAssertLessThanOrEqual(stableScore.ciHigh, 1)
        XCTAssertLessThanOrEqual(stableScore.ciLow, stableScore.ciHigh)

        XCTAssertGreaterThan(severeScore.value, stableScore.value)
    }

    func testUncertaintyShrinksWithMoreData() {
        let scenario = RealisticMoodDatasetFactory.makeScenario(days: 90).entries
        let shortSeries = FeatureStoreService.buildVectors(entries: Array(scenario.prefix(8)))
        let longSeries = FeatureStoreService.buildVectors(entries: Array(scenario.prefix(56)))

        let shortScore = RiskForecastService.forecast7dRisk(vectors: shortSeries)
        let longScore = RiskForecastService.forecast7dRisk(vectors: longSeries)

        XCTAssertLessThan(longScore.ciWidth, shortScore.ciWidth)
        XCTAssertLessThan(longScore.calibrationError, shortScore.calibrationError)
    }
}
