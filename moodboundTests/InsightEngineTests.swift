import XCTest
@testable import moodbound

final class InsightEngineTests: XCTestCase {

    // MARK: - Trend descriptions

    func testTrendDescriptionConsistentlyLow() {
        let desc = InsightEngine.trendDescription(-2.0)
        XCTAssertTrue(desc.lowercased().contains("low"))
    }

    func testTrendDescriptionABitLow() {
        let desc = InsightEngine.trendDescription(-1.0)
        XCTAssertTrue(desc.lowercased().contains("low"))
    }

    func testTrendDescriptionSteady() {
        let desc = InsightEngine.trendDescription(0.0)
        XCTAssertTrue(desc.lowercased().contains("steady"))
    }

    func testTrendDescriptionRunningHigh() {
        let desc = InsightEngine.trendDescription(1.0)
        XCTAssertTrue(desc.lowercased().contains("high"))
    }

    func testTrendDescriptionQuiteHigh() {
        let desc = InsightEngine.trendDescription(2.0)
        XCTAssertTrue(desc.lowercased().contains("high"))
    }

    func testTrendDescriptionBoundaries() {
        // Each boundary value should return a non-empty string
        let values: [Double] = [-3, -1.5, -0.5, 0, 0.5, 1.5, 3]
        for v in values {
            XCTAssertFalse(InsightEngine.trendDescription(v).isEmpty, "empty for \(v)")
        }
    }

    // MARK: - Snapshot with realistic data

    func testSnapshotWithRealisticData() {
        // Use enough days and anchor now to the end of the dataset so avg7/avg30
        // windows have entries.
        let now = Date()
        var entries: [MoodEntry] = []
        let cal = Calendar.current
        for i in 0..<60 {
            let date = cal.date(byAdding: .day, value: -i, to: now)!
            entries.append(MoodEntry(
                timestamp: date, moodLevel: [-1, 0, 1, 0, -1, 1][i % 6],
                energy: 3, sleepHours: 7, irritability: 0, anxiety: 0, note: ""
            ))
        }
        let snapshot = InsightEngine.snapshot(entries: entries, now: now)

        XCTAssertGreaterThanOrEqual(snapshot.streakDays, 0)
        XCTAssertNotNil(snapshot.avg7)
        XCTAssertNotNil(snapshot.avg30)

        if let avg7 = snapshot.avg7 {
            XCTAssertTrue((-3.0...3.0).contains(avg7))
        }
        if let avg30 = snapshot.avg30 {
            XCTAssertTrue((-3.0...3.0).contains(avg30))
        }
    }

    func testSnapshotWithEmptyEntries() {
        let snapshot = InsightEngine.snapshot(entries: [], now: Date())
        XCTAssertEqual(snapshot.streakDays, 0)
        XCTAssertNil(snapshot.avg7)
        XCTAssertNil(snapshot.avg30)
        XCTAssertEqual(snapshot.lowSleepCount14d, 0)
        XCTAssertEqual(snapshot.highSleepCount14d, 0)
        XCTAssertNil(snapshot.medicationAdherenceRate14d)
        XCTAssertNil(snapshot.topTrigger14d)
    }

    func testSnapshotSafetyNeverNil() {
        let scenario = RealisticMoodDatasetFactory.makeScenario(days: 60)
        let snapshot = InsightEngine.snapshot(entries: scenario.entries, now: Date())

        XCTAssertGreaterThanOrEqual(snapshot.safety.confidence, 0)
        XCTAssertLessThanOrEqual(snapshot.safety.confidence, 1)
        XCTAssertGreaterThanOrEqual(snapshot.safety.posteriorRisk, 0)
    }

    func testSnapshotSleepCounts() {
        // Create entries with known sleep values
        var entries: [MoodEntry] = []
        let now = Date()
        let cal = Calendar.current

        for i in 0..<14 {
            let date = cal.date(byAdding: .day, value: -i, to: now)!
            let sleep: Double = i < 5 ? 4.0 : (i < 8 ? 11.0 : 7.5)
            entries.append(MoodEntry(
                timestamp: date, moodLevel: 0, energy: 3,
                sleepHours: sleep, irritability: 0, anxiety: 0, note: ""
            ))
        }

        let snapshot = InsightEngine.snapshot(entries: entries, now: now)
        XCTAssertEqual(snapshot.lowSleepCount14d, 5)
        XCTAssertEqual(snapshot.highSleepCount14d, 3)
    }
}
