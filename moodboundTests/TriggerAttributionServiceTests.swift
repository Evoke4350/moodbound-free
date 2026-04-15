import XCTest
@testable import moodbound

final class TriggerAttributionServiceTests: XCTestCase {
    func testRankIsStableUnderMinorNoise() {
        let entries = RealisticMoodDatasetFactory.makeScenario(days: 84).entries
        let vectors = FeatureStoreService.buildVectors(entries: entries)
        var events = toSignalEvents(entries: entries)
        events.append(contentsOf: caffeineNoise(vectors: vectors))

        let ranked = TriggerAttributionService.rank(vectors: vectors, triggerEvents: events, topK: 3)
        XCTAssertEqual(ranked.first?.triggerName, "Stress")
    }

    func testSyntheticTopKHitRateIncludesKnownContributor() {
        let scenario = RealisticMoodDatasetFactory.makeScenario(days: 96).entries
        let vectors = FeatureStoreService.buildVectors(entries: scenario)
        let anchors = Array(vectors.dropFirst(18).prefix(56)).map(\.timestamp)

        let datasetA = syntheticDataset(
            vectors: vectors,
            anchors: anchors,
            primary: "Stress",
            secondary: "Conflict"
        )
        let datasetB = syntheticDataset(
            vectors: vectors,
            anchors: anchors,
            primary: "Conflict",
            secondary: "Sleep Loss"
        )
        let runs = [datasetA, datasetB]

        let hitCount = runs.reduce(0) { count, run in
            let ranked = TriggerAttributionService.rank(vectors: run.vectors, triggerEvents: run.events, topK: 2)
            return count + (ranked.contains(where: { $0.triggerName == run.primary }) ? 1 : 0)
        }

        XCTAssertGreaterThanOrEqual(Double(hitCount) / Double(runs.count), 1.0)
    }

    private func syntheticDataset(
        vectors: [TemporalFeatureVector],
        anchors: [Date],
        primary: String,
        secondary: String
    ) -> (vectors: [TemporalFeatureVector], events: [TriggerSignalEvent], primary: String) {
        let events = anchors.enumerated().map { idx, timestamp in
            TriggerSignalEvent(
                timestamp: timestamp,
                triggerName: idx % 3 == 0 ? secondary : primary,
                intensity: idx % 3 == 0 ? 1 : 3
            )
        }
        return (vectors, events, primary)
    }

    private func toSignalEvents(entries: [MoodEntry]) -> [TriggerSignalEvent] {
        entries.flatMap { entry in
            entry.triggerEvents.compactMap { event in
                guard let triggerName = event.trigger?.name, !triggerName.isEmpty else { return nil }
                return TriggerSignalEvent(
                    timestamp: event.timestamp,
                    triggerName: triggerName,
                    intensity: event.intensity
                )
            }
        }
    }

    private func caffeineNoise(vectors: [TemporalFeatureVector]) -> [TriggerSignalEvent] {
        vectors
            .enumerated()
            .filter { index, _ in index % 6 == 0 }
            .map { _, vector in
                TriggerSignalEvent(
                    timestamp: vector.timestamp,
                    triggerName: "Caffeine",
                    intensity: 1
                )
            }
    }
}
