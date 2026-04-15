import XCTest
@testable import moodbound

final class Phase6ReplayTests: XCTestCase {
    func testPipelineReplayProducesDeterministicOutputs() {
        let entries = RealisticMoodDatasetFactory.makeScenario(days: 84).entries
        let vectors = FeatureStoreService.buildVectors(entries: entries)
        let latent = LatentStateService.inferStates(vectors: vectors)
        let changes = ChangePointService.detect(vectors: vectors)
        let rawForecast = RiskForecastService.forecast7dRisk(vectors: vectors)
        let forecast = ConformalCalibrationService.conformalize(raw: rawForecast, vectors: vectors)
        let bocpd = BayesianOnlineChangePointService.detect(vectors: vectors)
        let wasserstein = WassersteinDriftService.assess(vectors: vectors)
        let bayesian = BayesianSafetyEngine.assess(
            vectors: vectors,
            latentResult: latent,
            changePoints: changes,
            forecast: forecast,
            bayesianChangeProbability: bocpd.latestChangeProbability,
            wassersteinDriftScore: wasserstein.score
        )
        let attributions = TriggerAttributionService.rank(entries: entries, topK: 3)
        let trajectories = MedicationTrajectoryService.trajectories(entries: entries)
        let prompts = AdaptiveCheckinService.nextPrompts(
            entries: entries,
            vectors: vectors,
            forecast: forecast,
            attributions: attributions
        )
        let phenotype = DigitalPhenotypeService.cards(vectors: vectors)
        let narratives = InsightNarrativeComposer.compose(
            safety: bayesian,
            topAttribution: attributions.first,
            strongestProbe: DirectionalSignalService.probes(vectors: vectors).first,
            phenotype: phenotype
        )

        XCTAssertFalse(vectors.isEmpty)
        XCTAssertTrue(bayesian.posteriorRisk >= 0 && bayesian.posteriorRisk <= 1)
        XCTAssertTrue(forecast.ciWidth >= rawForecast.ciWidth)
        XCTAssertTrue(wasserstein.score >= 0)
        XCTAssertFalse(attributions.isEmpty)
        XCTAssertEqual(attributions.first?.triggerName, "Stress")
        XCTAssertEqual(phenotype.count, 3)
        XCTAssertFalse(prompts.isEmpty)
        XCTAssertFalse(narratives.isEmpty)
        XCTAssertFalse(trajectories.isEmpty)
    }
}
