import XCTest
@testable import moodbound

final class RealisticMoodDatasetFactoryTests: XCTestCase {
    func testScenarioContainsStructuredSignalsAndReasonableRanges() {
        let scenario = RealisticMoodDatasetFactory.makeScenario(days: 120)
        let entries = scenario.entries

        XCTAssertEqual(entries.count, 120)
        XCTAssertFalse(scenario.medications.isEmpty)
        XCTAssertFalse(scenario.triggers.isEmpty)

        let moodRange = entries.map(\.moodLevel)
        XCTAssertGreaterThanOrEqual(moodRange.min() ?? 0, -3)
        XCTAssertLessThanOrEqual(moodRange.max() ?? 0, 3)

        let sleepMin = entries.map(\.sleepHours).min() ?? 0
        let sleepMax = entries.map(\.sleepHours).max() ?? 0
        XCTAssertGreaterThanOrEqual(sleepMin, 3.5)
        XCTAssertLessThanOrEqual(sleepMax, 12.0)

        let medEventCount = entries.flatMap(\.medicationAdherenceEvents).count
        XCTAssertGreaterThanOrEqual(medEventCount, 200)

        let stressEvents = entries
            .flatMap(\.triggerEvents)
            .filter { $0.trigger?.name == "Stress" }
            .count
        XCTAssertGreaterThan(stressEvents, 20)
    }
}
