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

    // Regression: counts.max(by:) iterated dictionary order, so two triggers
    // tied on count returned a non-deterministic name (Anvil sometimes,
    // Stress others). The fix sorts by (-count, name) so ties resolve
    // alphabetically. Repeating the snapshot must always pick the same name.
    func testSnapshotTopTriggerTieBreakIsDeterministicAndAlphabetical() {
        let now = Date()
        let cal = Calendar.current
        let alpha = TriggerFactor(name: "Alpha", category: "social")
        let zulu = TriggerFactor(name: "Zulu", category: "social")

        var entries: [MoodEntry] = []
        for i in 0..<6 {
            let date = cal.date(byAdding: .day, value: -i, to: now)!
            let entry = MoodEntry(timestamp: date, moodLevel: 0, energy: 3, sleepHours: 7, irritability: 0, anxiety: 0, note: "")
            // Equal count: 3 Alpha events and 3 Zulu events across 6 days.
            let trigger = i % 2 == 0 ? alpha : zulu
            entry.triggerEvents = [TriggerEvent(timestamp: date, intensity: 2, trigger: trigger, moodEntry: entry)]
            entries.append(entry)
        }

        let topNames = (0..<5).map { _ in InsightEngine.snapshot(entries: entries, now: now).topTrigger14d }
        XCTAssertEqual(Set(topNames).count, 1, "topTrigger14d should be stable across repeated calls")
        XCTAssertEqual(topNames.first ?? nil, "Alpha", "ties should resolve to the alphabetically first name")
    }

    // Regression: with only 2 entries, the previous engine still emitted
    // confident "shift" / "bumpier than usual" narrative bullets and the
    // outlook badge could read "Rough patch", since none of those
    // signals had a sample-size guard. The fix routes user-facing narrative
    // through an EvidenceLevel gate; below 4 recent observations we surface
    // a single "still learning your patterns" message instead.
    func testSnapshotEvidenceLevelHedgesNarrativeWhenSparse() {
        let now = Date()
        let cal = Calendar.current
        let entries: [MoodEntry] = (0..<2).map { i in
            MoodEntry(
                timestamp: cal.date(byAdding: .day, value: -i, to: now)!,
                moodLevel: 3, energy: 5, sleepHours: 4, irritability: 3, anxiety: 3, note: ""
            )
        }
        let snapshot = InsightEngine.snapshot(entries: entries, now: now)
        XCTAssertEqual(snapshot.evidenceLevel, .insufficient)
        XCTAssertEqual(snapshot.observationsLast14d, 2)
        XCTAssertEqual(snapshot.safety.evidenceSignals.count, 1)
        XCTAssertTrue(snapshot.safety.evidenceSignals.first?.lowercased().contains("learning") ?? false)
    }

    func testSnapshotEvidenceLevelEstablishedWithFullWindow() {
        let now = Date()
        let cal = Calendar.current
        let entries: [MoodEntry] = (0..<14).map { i in
            MoodEntry(
                timestamp: cal.date(byAdding: .day, value: -i, to: now)!,
                moodLevel: 0, energy: 3, sleepHours: 7, irritability: 0, anxiety: 0, note: ""
            )
        }
        let snapshot = InsightEngine.snapshot(entries: entries, now: now)
        XCTAssertEqual(snapshot.evidenceLevel, .established)
        XCTAssertEqual(snapshot.observationsLast14d, 14)
    }

    func testSnapshotRainyDeltaCountsOpenMeteoRainCodes() {
        let now = Date()
        let cal = Calendar.current
        let rainy = MoodEntry(
            timestamp: cal.date(byAdding: .day, value: -1, to: now)!,
            moodLevel: -2,
            energy: 3,
            sleepHours: 7,
            irritability: 0,
            anxiety: 0,
            note: "",
            weatherCity: "Seattle",
            weatherCode: 80, // Open-Meteo rain shower code
            weatherSummary: "Rain",
            temperatureC: 12,
            precipitationMM: 0
        )
        let clear = MoodEntry(
            timestamp: now,
            moodLevel: 1,
            energy: 3,
            sleepHours: 7,
            irritability: 0,
            anxiety: 0,
            note: "",
            weatherCity: "Seattle",
            weatherCode: 0,
            weatherSummary: "Clear",
            temperatureC: 18,
            precipitationMM: 0
        )

        let snapshot = InsightEngine.snapshot(entries: [clear, rainy], now: now)
        XCTAssertNotNil(snapshot.rainyMoodDelta)
        XCTAssertEqual(snapshot.rainyMoodDelta ?? 0, -3, accuracy: 0.001)
    }
}
