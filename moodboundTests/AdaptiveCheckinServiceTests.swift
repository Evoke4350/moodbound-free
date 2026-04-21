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

    // Regression: sleepStdDev previously included sleepHours == 0 (the
    // "unknown" sentinel), so a user with real consistent sleep but a few
    // HealthKit misses looked hugely irregular and sleep-routine got surfaced
    // as a top-information prompt. With zeros excluded, a user whose only
    // sleep signal is a handful of logged 7-8h nights should not trigger the
    // sleep-routine prompt as a top-gain candidate.
    func testUnknownSleepDoesNotInflateSleepPromptGain() {
        let now = Date()
        let cal = Calendar.current
        // 14 days where most are unknown (0h) and a few are steady 7.5h —
        // the actual recorded sleep is consistent; only unknowns vary.
        let entries: [MoodEntry] = (0..<14).map { i in
            let sleep: Double = (i % 4 == 0) ? 7.5 : 0
            return MoodEntry(
                timestamp: cal.date(byAdding: .day, value: -i, to: now)!,
                moodLevel: 0, energy: 3, sleepHours: sleep,
                irritability: 0, anxiety: 0, note: ""
            )
        }
        let vectors = FeatureStoreService.buildVectors(entries: entries)
        let forecast = ProbabilisticScore(value: 0.3, ciLow: 0.15, ciHigh: 0.5, calibrationError: 0.05)

        let prompts = AdaptiveCheckinService.nextPrompts(
            entries: entries,
            vectors: vectors,
            forecast: forecast,
            attributions: [],
            maxPrompts: 3
        )
        let sleepPrompt = prompts.first(where: { $0.id == "sleep-routine" })
        XCTAssertNil(sleepPrompt,
            "sleep-routine must not surface when actual recorded sleep is consistent — unknowns should not inflate its information gain")
    }
}
