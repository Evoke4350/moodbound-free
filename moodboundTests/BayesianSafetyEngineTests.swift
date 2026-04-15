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
