import XCTest
@testable import moodbound

/// Tests for the new InsightSnapshot fields exposed in build 7 (B1/B2):
/// the raw forecast point + CI bounds and the per-day latent state
/// posteriors. These guarantee that views downstream (HistoryView
/// forecast outlook card, mood chart background overlay, NewEntryView
/// adaptive prompt header) can rely on well-formed data on non-empty
/// input and on safe fallbacks on near-empty input.
final class InsightSnapshotBuild7Tests: XCTestCase {
    private let referenceNow = Date(timeIntervalSince1970: 1_736_000_000) // 2025-01-04 UTC-ish, stable anchor

    func testSnapshotExposesForecastPointAndInterval() {
        let scenario = RealisticMoodDatasetFactory.makeScenario(days: 30)
        let snapshot = InsightEngine.snapshot(entries: scenario.entries, now: referenceNow)

        XCTAssertGreaterThanOrEqual(snapshot.forecastValue, 0.0)
        XCTAssertLessThanOrEqual(snapshot.forecastValue, 1.0)
        XCTAssertGreaterThanOrEqual(snapshot.forecastCILow, 0.0)
        XCTAssertLessThanOrEqual(snapshot.forecastCIHigh, 1.0)
        XCTAssertLessThanOrEqual(
            snapshot.forecastCILow,
            snapshot.forecastCIHigh,
            "Forecast CI must be ordered low ≤ high"
        )
        // The point estimate should live inside the interval for a valid
        // calibrated forecast. Allow equality at the boundary.
        XCTAssertGreaterThanOrEqual(snapshot.forecastValue, snapshot.forecastCILow)
        XCTAssertLessThanOrEqual(snapshot.forecastValue, snapshot.forecastCIHigh)
    }

    func testSnapshotExposesLatentPosteriorsForChartOverlay() {
        let scenario = RealisticMoodDatasetFactory.makeScenario(days: 30)
        let snapshot = InsightEngine.snapshot(entries: scenario.entries, now: referenceNow)

        XCTAssertFalse(
            snapshot.latentPosteriors.isEmpty,
            "Latent posteriors must be available for HistoryView to render the B2 state overlay"
        )
        // Each posterior should be a valid probability distribution.
        for posterior in snapshot.latentPosteriors.prefix(5) {
            let sum = posterior.distribution.sum
            XCTAssertGreaterThan(sum, 0.99)
            XCTAssertLessThan(sum, 1.01)
        }
    }

    func testSnapshotOnEmptyHistoryDoesNotCrashAndReturnsSafeForecast() {
        // Near-empty history: the forecast should still produce valid
        // bounds so the B1 card doesn't render NaN or divide-by-zero.
        let scenario = RealisticMoodDatasetFactory.makeScenario(days: 1)
        let snapshot = InsightEngine.snapshot(entries: scenario.entries, now: referenceNow)

        XCTAssertFalse(snapshot.forecastValue.isNaN)
        XCTAssertFalse(snapshot.forecastCILow.isNaN)
        XCTAssertFalse(snapshot.forecastCIHigh.isNaN)
        XCTAssertLessThanOrEqual(snapshot.forecastCILow, snapshot.forecastCIHigh)
    }
}
