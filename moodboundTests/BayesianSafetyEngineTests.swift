import XCTest
@testable import moodbound

final class BayesianSafetyEngineTests: XCTestCase {
    func testHigherRiskScenarioProducesHigherPosteriorAndSeverity() {
        let scenario = RealisticMoodDatasetFactory.makeScenario(days: 140).entries
        let lowRisk = FeatureStoreService.buildVectors(entries: Array(scenario.prefix(28)))
        let highRisk = FeatureStoreService.buildVectors(entries: Array(scenario[112..<140]))

        let low = evaluate(vectors: lowRisk)
        let high = evaluate(vectors: highRisk)

        XCTAssertGreaterThan(high.posteriorRisk, low.posteriorRisk)
        XCTAssertTrue(rank(high.severity) >= rank(low.severity))
        XCTAssertFalse(high.evidence.signals.isEmpty)
    }

    // Regression: pre-shrinkage, two consecutive high-distress days could
    // shove the likelihood ratio enough to escalate severity to .high or
    // .critical from N=2 alone. The fix pulls posteriorRisk toward the
    // prior (0.22) with weight Min(1, N/14), so a sparse-but-extreme series
    // can no longer trip safety escalation by itself. The same data with
    // N≥14 should still produce a meaningful escalation.
    func testSparseDistressDoesNotEscalateSeverity() {
        let now = Date()
        let cal = Calendar.current
        // Two days of severe distress, no preceding history.
        let sparse: [MoodEntry] = (0..<2).map { i in
            MoodEntry(
                timestamp: cal.date(byAdding: .day, value: -i, to: now)!,
                moodLevel: 3, energy: 5, sleepHours: 4, irritability: 3, anxiety: 3, note: ""
            )
        }
        let sparseVectors = FeatureStoreService.buildVectors(entries: sparse)
        let sparseResult = evaluate(vectors: sparseVectors)
        XCTAssertLessThanOrEqual(rank(sparseResult.severity), rank(.elevated))

        // Same distress pattern over a full 14-day window should reveal the
        // true risk and escalate beyond .none.
        let full: [MoodEntry] = (0..<14).map { i in
            MoodEntry(
                timestamp: cal.date(byAdding: .day, value: -i, to: now)!,
                moodLevel: 3, energy: 5, sleepHours: 4, irritability: 3, anxiety: 3, note: ""
            )
        }
        let fullVectors = FeatureStoreService.buildVectors(entries: full)
        let fullResult = evaluate(vectors: fullVectors)
        XCTAssertGreaterThan(rank(fullResult.severity), rank(.none))
        XCTAssertGreaterThan(fullResult.posteriorRisk, sparseResult.posteriorRisk)
    }

    func testConfidenceBounds() {
        let scenario = RealisticMoodDatasetFactory.makeScenario(days: 60).entries
        let vectors = FeatureStoreService.buildVectors(entries: Array(scenario[20..<40]))
        let result = evaluate(vectors: vectors)

        XCTAssertGreaterThanOrEqual(result.confidence, 0)
        XCTAssertLessThanOrEqual(result.confidence, 1)
    }

    private func evaluate(vectors: [TemporalFeatureVector]) -> BayesianSafetyResult {
        let latent = LatentStateService.inferStates(vectors: vectors)
        let changes = ChangePointService.detect(vectors: vectors)
        let forecast = RiskForecastService.forecast7dRisk(vectors: vectors)
        return BayesianSafetyEngine.assess(
            vectors: vectors,
            latentResult: latent,
            changePoints: changes,
            forecast: forecast
        )
    }

    private func rank(_ severity: SafetySeverity) -> Int {
        switch severity {
        case .none: return 0
        case .elevated: return 1
        case .high: return 2
        case .critical: return 3
        }
    }
}
