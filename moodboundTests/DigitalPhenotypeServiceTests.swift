import XCTest
@testable import moodbound

final class DigitalPhenotypeServiceTests: XCTestCase {
    func testSleepRegularityMetricReflectsStableSleep() {
        let entries = Array(RealisticMoodDatasetFactory.makeScenario(days: 30).entries[0..<20])
        let vectors = FeatureStoreService.buildVectors(entries: entries)

        let cards = DigitalPhenotypeService.cards(vectors: vectors)
        let sleep = cards.first(where: { $0.id == "sleep-regularity" })
        XCTAssertNotNil(sleep)
        XCTAssertGreaterThan((sleep?.metricValue ?? 0), 65)
    }

    func testInsufficientDataCardsReturnedForSmallSeries() {
        let entries = RealisticMoodDatasetFactory.makeScenario(days: 3).entries
        let vectors = FeatureStoreService.buildVectors(entries: entries)

        let cards = DigitalPhenotypeService.cards(vectors: vectors)
        XCTAssertTrue(cards.allSatisfy { !$0.isSufficientData })
    }

    func testCardsHandleLongSeriesSuffixWithoutIndexCrash() {
        let entries = RealisticMoodDatasetFactory.makeScenario(days: 90).entries
        let vectors = FeatureStoreService.buildVectors(entries: entries)

        let cards = DigitalPhenotypeService.cards(vectors: vectors)

        XCTAssertEqual(cards.count, 3)
        XCTAssertTrue(cards.contains(where: { $0.id == "recovery-half-life" }))
    }
}
