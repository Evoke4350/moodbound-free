import XCTest
@testable import moodbound

final class DirectionalSignalServiceTests: XCTestCase {
    func testDetectsLaggedDirectionalHint() {
        let anchors = RealisticMoodDatasetFactory.makeScenario(days: 24).entries.map(\.timestamp)
        let deficits = (0..<24).map { 0.15 * Double($0) }
        let vectors: [TemporalFeatureVector] = anchors.enumerated().map { index, timestamp in
            let moodLag = index == 0 ? 0.0 : deficits[index - 1]
            return TemporalFeatureVector(
                timestamp: timestamp,
                moodLevel: moodLag,
                sleepHours: 7.0 - deficits[index],
                energy: 3.0 + (0.1 * Double(index % 3)),
                anxiety: 1.0 + (0.03 * Double(index)),
                irritability: 1.0,
                medAdherenceRate7d: 0.75,
                triggerLoad7d: 1.0 + (0.06 * Double(index)),
                volatility7d: 0.7,
                circadianDrift7d: 0.3
            )
        }

        let probes = DirectionalSignalService.probes(vectors: vectors)
        XCTAssertFalse(probes.isEmpty)
        XCTAssertTrue(probes.contains { $0.source == "Sleep Deficit" })
    }

    func testEveryProbeIncludesNonDiagnosticCaveat() {
        let entries = RealisticMoodDatasetFactory.makeScenario(days: 28).entries
        let vectors = entries.enumerated().map { index, entry in
            TemporalFeatureVector(
                timestamp: entry.timestamp,
                moodLevel: index == 0 ? 0.0 : max(0, 7.0 - entries[index - 1].sleepHours),
                sleepHours: entry.sleepHours,
                energy: 3.0,
                anxiety: entry.anxiety == 0 ? 1.0 : Double(entry.anxiety),
                irritability: 1.0,
                medAdherenceRate7d: 0.6,
                triggerLoad7d: 1.1 + (0.04 * Double(index)),
                volatility7d: 0.8,
                circadianDrift7d: 0.3
            )
        }

        let probes = DirectionalSignalService.probes(vectors: vectors)
        XCTAssertFalse(probes.isEmpty)
        XCTAssertTrue(probes.allSatisfy { $0.caveat.contains("not diagnostic") })
    }
}
