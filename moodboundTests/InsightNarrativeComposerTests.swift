import XCTest
@testable import moodbound

final class InsightNarrativeComposerTests: XCTestCase {
    private let calendar = Calendar(identifier: .gregorian)

    func testNarrativesIncludeConfidenceAndEvidenceWindow() {
        let safety = BayesianSafetyResult(
            severity: .elevated,
            posteriorRisk: 0.52,
            confidence: 0.72,
            evidence: ModelEvidence(
                windowStart: date(2026, 4, 1, 9, 0),
                windowEnd: date(2026, 4, 12, 9, 0),
                signals: ["7-day forecast risk is elevated."]
            ),
            recommendedActions: ["Review your safety plan"],
            messages: ["Patterns were detected."]
        )
        let topAttribution = TriggerAttribution(
            triggerName: "Stress",
            score: 0.22,
            confidence: 0.7,
            evidenceWindowStart: date(2026, 4, 2, 9, 0),
            evidenceWindowEnd: date(2026, 4, 12, 9, 0),
            supportingEvents: 6
        )
        let probe = DirectionalSignalProbe(
            source: "Sleep Deficit",
            target: "Next-Day Mood Elevation",
            lagDays: 1,
            strength: 0.51,
            confidence: 0.68,
            caveat: DirectionalSignalService.standardCaveat
        )
        let phenotype = [
            DigitalPhenotypeCard(
                id: "sleep-regularity",
                title: "Sleep Regularity",
                metricValue: 78,
                uncertainty: 0.2,
                interpretationBand: "Stable",
                isSufficientData: true
            )
        ]

        let cards = InsightNarrativeComposer.compose(
            safety: safety,
            topAttribution: topAttribution,
            strongestProbe: probe,
            phenotype: phenotype
        )

        XCTAssertFalse(cards.isEmpty)
        XCTAssertTrue(cards.allSatisfy { !$0.evidenceWindow.isEmpty })
        XCTAssertTrue(cards.allSatisfy { $0.confidence >= 0 && $0.confidence <= 1 })
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
        var components = DateComponents()
        components.calendar = calendar
        components.timeZone = TimeZone(secondsFromGMT: 0)
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        return components.date!
    }
}
