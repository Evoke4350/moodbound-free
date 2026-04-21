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

    // Regression for the double-shrinkage interaction: at N=6 with severe
    // distress, the previous chain (RiskForecastService shrunk -> fed into
    // BayesianSafetyEngine LR -> linearly shrunk again) compounded so hard
    // that posteriorRisk landed near the prior (0.22). With (a) the LR now
    // reading forecast.rawValue and (b) the sqrt curve, the same window
    // should bind to at least .elevated.
    func testIntermediateSampleStrongDistressEscalates() {
        let now = Date()
        let cal = Calendar.current
        let entries: [MoodEntry] = (0..<6).map { i in
            MoodEntry(
                timestamp: cal.date(byAdding: .day, value: -i, to: now)!,
                moodLevel: 3, energy: 5, sleepHours: 4, irritability: 3, anxiety: 3, note: ""
            )
        }
        let vectors = FeatureStoreService.buildVectors(entries: entries)
        let result = evaluate(vectors: vectors)
        XCTAssertGreaterThanOrEqual(rank(result.severity), rank(.elevated),
            "N=6 with severe distress should escalate beyond .none after the double-shrinkage fix")
        // Ceiling: routing forecast.rawValue (vs. shrunk value) into the LR
        // raises its magnitude. Six days should not be enough to push severity
        // all the way to .critical — that would mean the user can hit the
        // top alert tier from less than a week of data, which is the failure
        // mode the original shrinkage was designed to prevent.
        XCTAssertLessThan(rank(result.severity), rank(.critical),
            "N=6 must not be enough data to escalate to .critical, even with severe distress")
        XCTAssertGreaterThan(result.posteriorRisk, 0.22,
            "Posterior should rise meaningfully above the prior, not collapse back into it")
    }

    // Regression: sleepHours == 0 is the app's "unknown" sentinel (HealthKit
    // miss or user skipped). Previously lowSleepRate was computed as
    // `$0.sleepHours < 6.0`, which treated a run of unlogged days as 14 days
    // of severe sleep deficit and inflated posteriorRisk. Two parallel
    // windows — one with 0h unknowns, one with a benign 7h — must now produce
    // effectively the same posterior, because the unknown days carry no
    // evidence in either direction.
    func testUnknownSleepDaysDoNotInflatePosteriorRisk() {
        let now = Date()
        let cal = Calendar.current
        let unknownSleep: [MoodEntry] = (0..<14).map { i in
            MoodEntry(
                timestamp: cal.date(byAdding: .day, value: -i, to: now)!,
                moodLevel: 0, energy: 3, sleepHours: 0, irritability: 0, anxiety: 0, note: ""
            )
        }
        let benignSleep: [MoodEntry] = (0..<14).map { i in
            MoodEntry(
                timestamp: cal.date(byAdding: .day, value: -i, to: now)!,
                moodLevel: 0, energy: 3, sleepHours: 7, irritability: 0, anxiety: 0, note: ""
            )
        }
        let unknownResult = evaluate(vectors: FeatureStoreService.buildVectors(entries: unknownSleep))
        let benignResult = evaluate(vectors: FeatureStoreService.buildVectors(entries: benignSleep))

        XCTAssertEqual(unknownResult.posteriorRisk, benignResult.posteriorRisk, accuracy: 0.02,
            "sleepHours==0 (unknown) must not drive posteriorRisk up vs. a benign 7h day")
        XCTAssertEqual(rank(unknownResult.severity), rank(benignResult.severity),
            "unknown sleep must not escalate severity")
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
