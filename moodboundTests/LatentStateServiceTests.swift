import XCTest
@testable import moodbound

final class LatentStateServiceTests: XCTestCase {
    func testPosteriorProbabilitiesAreNormalized() {
        let entries = RealisticMoodDatasetFactory.makeScenario(days: 12).entries
        let vectors = FeatureStoreService.buildVectors(entries: entries)

        let result = LatentStateService.inferStates(vectors: vectors)
        XCTAssertEqual(result.modelVersion, LatentStateService.modelVersion)
        XCTAssertEqual(result.posteriors.count, vectors.count)

        for day in result.posteriors {
            XCTAssertEqual(day.distribution.sum, 1.0, accuracy: 0.0001)
        }
    }

    func testSyntheticBacktestRecoversStateBlocks() {
        let entries = RealisticMoodDatasetFactory.makeScenario(days: 150).entries
        let vectors = FeatureStoreService.buildVectors(entries: entries)

        let result = LatentStateService.inferStates(vectors: vectors)
        let posteriors = result.posteriors

        let depressiveBlock = posteriors[42..<84].map { $0.distribution.dominantState }
        let elevatedBlock = posteriors[112..<147].map { $0.distribution.dominantState }

        let depressiveHits = depressiveBlock.filter { $0 == .depressive }.count
        let elevatedHits = elevatedBlock.filter { $0 == .elevated }.count

        XCTAssertGreaterThanOrEqual(depressiveHits, 30)
        XCTAssertGreaterThanOrEqual(elevatedHits, 25)
    }

    func testSmoothingReducesSingleDayOutlierFlipsAgainstNaiveMapping() {
        let entries = RealisticMoodDatasetFactory.makeScenario(days: 20).entries
        var vectors = entries.map { entry in
            TemporalFeatureVector(
                timestamp: entry.timestamp,
                moodLevel: 0.0,
                sleepHours: 7.4,
                energy: 3.0,
                anxiety: 1.1,
                irritability: 1.0,
                medAdherenceRate7d: 0.9,
                triggerLoad7d: 0.8,
                volatility7d: 0.35,
                circadianDrift7d: 0.2
            )
        }
        vectors[9] = TemporalFeatureVector(
            timestamp: vectors[9].timestamp,
            moodLevel: 1.0,
            sleepHours: 6.0,
            energy: 3.8,
            anxiety: 1.5,
            irritability: 1.4,
            medAdherenceRate7d: 0.8,
            triggerLoad7d: 1.1,
            volatility7d: 0.9,
            circadianDrift7d: 0.3
        )

        let naive = vectors.map(LatentStateService.naiveState(for:))
        let smoothed = LatentStateService.inferStates(vectors: vectors).posteriors.map { $0.distribution.dominantState }

        XCTAssertLessThan(flipCount(in: smoothed), flipCount(in: naive))
    }

    private func flipCount(in states: [LatentMoodState]) -> Int {
        guard states.count > 1 else { return 0 }
        var flips = 0
        for index in 1..<states.count where states[index] != states[index - 1] {
            flips += 1
        }
        return flips
    }
}
