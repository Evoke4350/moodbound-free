import XCTest
@testable import moodbound

final class PerformanceBudgetTests: XCTestCase {
    func testRiskForecastPerformanceFor365Entries() {
        let entries = makeEntries(count: 365)
        let vectors = FeatureStoreService.buildVectors(entries: entries)

        measure(metrics: [XCTClockMetric()]) {
            _ = RiskForecastService.forecast7dRisk(vectors: vectors)
        }
    }

    func testFeatureMaterializationPerformanceFor365Entries() {
        let entries = makeEntries(count: 365)

        measure(metrics: [XCTClockMetric()]) {
            _ = FeatureStoreService.materialize(entries: entries)
        }
    }

    private func makeEntries(count: Int) -> [MoodEntry] {
        RealisticMoodDatasetFactory.makeScenario(days: count).entries
    }
}
