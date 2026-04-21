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

    // Regression: with the previous integer-division formula `recent.count / 3`,
    // a single change point saturated to 1.0 across N=1..5, then dropped
    // discontinuously at N=6 (to 0.5). The fix uses Double division, which
    // keeps the rate strictly decreasing as N grows past the change count.
    func testRecentChangeRateScalesSmoothlyWithSmallN() {
        // With 1 change point, the rate must be strictly monotone-decreasing
        // from N=4 upward — the buggy integer-division formula returned 1.0
        // for both N=4 and N=5.
        let r4 = RiskForecastService.recentChangeRate(changeCount: 1, recentCount: 4)
        let r5 = RiskForecastService.recentChangeRate(changeCount: 1, recentCount: 5)
        let r6 = RiskForecastService.recentChangeRate(changeCount: 1, recentCount: 6)
        let r7 = RiskForecastService.recentChangeRate(changeCount: 1, recentCount: 7)
        XCTAssertGreaterThan(r4, r5)
        XCTAssertGreaterThan(r5, r6)
        XCTAssertGreaterThan(r6, r7)

        // Rate is bounded in [0, 1] and saturates only when changes ≥ N/3.
        XCTAssertEqual(RiskForecastService.recentChangeRate(changeCount: 0, recentCount: 14), 0)
        XCTAssertEqual(RiskForecastService.recentChangeRate(changeCount: 10, recentCount: 1), 1.0)
        XCTAssertEqual(RiskForecastService.recentChangeRate(changeCount: 1, recentCount: 3), 1.0, accuracy: 0.0001)
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
