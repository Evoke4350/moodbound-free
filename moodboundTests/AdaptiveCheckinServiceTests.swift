import XCTest
@testable import moodbound

final class AdaptiveCheckinServiceTests: XCTestCase {
    func testSelectsHighInformationPromptsFirst() {
        let entries = RealisticMoodDatasetFactory.makeScenario(days: 42).entries
        for (index, entry) in entries.enumerated() where index % 3 == 0 {
            entry.medicationAdherenceEvents = []
        }

        let vectors = FeatureStoreService.buildVectors(entries: entries)
        let forecast = ProbabilisticScore(value: 0.55, ciLow: 0.35, ciHigh: 0.78, calibrationError: 0.2)
        let attributions: [TriggerAttribution] = []

        let prompts = AdaptiveCheckinService.nextPrompts(
            entries: entries,
            vectors: vectors,
            forecast: forecast,
            attributions: attributions,
            maxPrompts: 3
        )

        XCTAssertFalse(prompts.isEmpty)
        XCTAssertLessThanOrEqual(prompts.count, 3)
        XCTAssertTrue(prompts.contains(where: { $0.id == "medication-adherence" || $0.id == "sleep-routine" }))
    }

    func testPromptListIsBounded() {
        let entries = RealisticMoodDatasetFactory.makeScenario(days: 20).entries
        let vectors = FeatureStoreService.buildVectors(entries: entries)
        let forecast = ProbabilisticScore(value: 0.4, ciLow: 0.2, ciHigh: 0.7, calibrationError: 0.1)
        let attributions = [
            TriggerAttribution(
                triggerName: "Stress",
                score: 0.2,
                confidence: 0.2,
                evidenceWindowStart: entries.first!.timestamp,
                evidenceWindowEnd: entries.last!.timestamp,
                supportingEvents: 4
            )
        ]

        let prompts = AdaptiveCheckinService.nextPrompts(
            entries: entries,
            vectors: vectors,
            forecast: forecast,
            attributions: attributions,
            maxPrompts: 2
        )
        XCTAssertLessThanOrEqual(prompts.count, 2)
    }
}
