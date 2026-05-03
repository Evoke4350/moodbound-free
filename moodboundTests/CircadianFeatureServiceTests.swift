import XCTest
@testable import moodbound

final class CircadianFeatureServiceTests: XCTestCase {
    private let calendar = Calendar(identifier: .gregorian)

    private struct LCRNG: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return state
        }
    }

    private func date(_ d: Int, hour: Int = 9) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 5, day: d, hour: hour))!
    }

    private func entry(
        day: Int,
        hour: Int = 8,
        sleep: Double = 7,
        steps: Int? = nil,
        mood: Int = 0
    ) -> MoodEntry {
        MoodEntry(
            timestamp: date(day, hour: hour),
            moodLevel: mood,
            energy: 3,
            sleepHours: sleep,
            irritability: 0,
            anxiety: 0,
            stepCount: steps
        )
    }

    // MARK: - Per-feature unit tests

    func testEmptyEntriesProducesEmptyVectorList() {
        XCTAssertTrue(CircadianFeatureService.vectors(entries: []).isEmpty)
    }

    func testSleepMidpointComputedFromWakeHourAndSleepHours() {
        // Wake at 7 AM after 7h sleep → midpoint 3.5
        let midpoint = CircadianFeatureService.approximateSleepMidpoint(
            sleepHours: 7,
            wakeReference: date(1, hour: 7),
            calendar: calendar
        )
        XCTAssertEqual(midpoint, 3.5, accuracy: 0.01)
    }

    func testSleepMidpointCappedAtNoonForLateMorningCheckins() {
        // Check-in at 3pm after 8h sleep would naively give midpoint 11,
        // but a 3pm reference is far past wake — cap at noon → midpoint 8.
        let midpoint = CircadianFeatureService.approximateSleepMidpoint(
            sleepHours: 8,
            wakeReference: date(1, hour: 15),
            calendar: calendar
        )
        XCTAssertEqual(midpoint, 8, accuracy: 0.01)
    }

    func testSingleNightMidpointVarianceIsNil() {
        let entries = [entry(day: 1, sleep: 7)]
        let v = CircadianFeatureService.vectors(entries: entries)
        XCTAssertNotNil(v.first?.sleepMidpoint)
        XCTAssertNil(v.first?.sleepMidpointVariance7d)
    }

    func testStandardDeviationMatchesKnownValue() {
        // values [1,2,3,4,5] → sample stdev = 1.5811...
        let result = CircadianFeatureService.standardDeviation([1, 2, 3, 4, 5])
        XCTAssertEqual(result!, 1.5811388, accuracy: 0.001)
    }

    func testHourlyAsleepStatesCoversNonWrappingNight() {
        // midnight..7am sleep: midpoint 3.5, 7h
        let states = CircadianFeatureService.hourlyAsleepStates(midpoint: 3.5, sleepHours: 7)
        for h in 0..<7 { XCTAssertTrue(states[h], "expected asleep at hour \(h)") }
        for h in 7..<24 { XCTAssertFalse(states[h], "expected awake at hour \(h)") }
    }

    func testHourlyAsleepStatesWrapsPastMidnight() {
        // Sleep 11pm..6am: midpoint 2.5, 7h → window [-1, 6).
        // Asleep hours: 23, 0, 1, 2, 3, 4, 5.
        let states = CircadianFeatureService.hourlyAsleepStates(midpoint: 2.5, sleepHours: 7)
        XCTAssertTrue(states[23])
        for h in 0..<6 { XCTAssertTrue(states[h], "expected asleep at hour \(h)") }
        for h in 6..<23 { XCTAssertFalse(states[h], "expected awake at hour \(h)") }
    }

    func testSleepRegularityIndexPerfectRoutineReturns100() {
        // Same sleep window every night for 7 days → SRI 100.
        var entries: [MoodEntry] = []
        for d in 1...8 { entries.append(entry(day: d, hour: 7, sleep: 7)) }
        let result = CircadianFeatureService.vectors(entries: entries).last
        XCTAssertNotNil(result?.sleepRegularityIndex)
        XCTAssertEqual(result!.sleepRegularityIndex!, 100, accuracy: 0.001)
    }

    func testSleepRegularityIndexShiftedScheduleScoresBelow100() {
        // Alternate wake at 6am vs 10am — schedules don't match 24h-shifted.
        var entries: [MoodEntry] = []
        for d in 1...8 {
            let wake = (d % 2 == 0) ? 6 : 10
            entries.append(entry(day: d, hour: wake, sleep: 7))
        }
        let result = CircadianFeatureService.vectors(entries: entries).last
        XCTAssertNotNil(result?.sleepRegularityIndex)
        XCTAssertLessThan(result!.sleepRegularityIndex!, 100)
    }

    func testCircadianPhaseZNeedsBaselineVariance() {
        // All same midpoint → variance 0 → phaseZ undefined.
        var entries: [MoodEntry] = []
        for d in 1...8 { entries.append(entry(day: d, hour: 7, sleep: 7)) }
        XCTAssertNil(CircadianFeatureService.vectors(entries: entries).last?.circadianPhaseZ)
    }

    func testCircadianPhaseZPositiveForPhaseDelay() {
        // Stable midpoint for 6 nights, then a sleep-in (delay).
        var entries: [MoodEntry] = []
        for d in 1...7 { entries.append(entry(day: d, hour: 7, sleep: 7)) }
        // Day 8: wake at 11am after 7h → midpoint = 11 - 3.5 = 7.5 (delay)
        entries.append(entry(day: 8, hour: 11, sleep: 7))
        let last = CircadianFeatureService.vectors(entries: entries).last
        XCTAssertNotNil(last?.circadianPhaseZ)
        XCTAssertGreaterThan(last!.circadianPhaseZ!, 0)
    }

    // MARK: - Property tests

    func testProperty_VectorsCoverEveryDayInSpan() {
        var rng = LCRNG(state: 0xC1AC)
        let span = 30
        var entries: [MoodEntry] = []
        for d in 1...span {
            // Skip ~30% of days
            if Bool.random(using: &rng) && Bool.random(using: &rng) { continue }
            entries.append(entry(day: d, sleep: Double.random(in: 5...9, using: &rng)))
        }
        guard !entries.isEmpty else { return }
        let vectors = CircadianFeatureService.vectors(entries: entries)
        let firstDay = calendar.startOfDay(for: entries.map(\.timestamp).min()!)
        let lastDay = calendar.startOfDay(for: entries.map(\.timestamp).max()!)
        let expectedDays = (calendar.dateComponents([.day], from: firstDay, to: lastDay).day ?? 0) + 1
        XCTAssertEqual(vectors.count, expectedDays)
    }

    func testProperty_AllNumericFieldsAreFiniteOrNil() {
        var rng = LCRNG(state: 0xF1A1)
        var entries: [MoodEntry] = []
        for d in 1...30 {
            entries.append(entry(
                day: d,
                hour: Int.random(in: 5...11, using: &rng),
                sleep: Double.random(in: 4...10, using: &rng),
                steps: Int.random(in: 1000...15000, using: &rng)
            ))
        }
        for vector in CircadianFeatureService.vectors(entries: entries) {
            for value in [
                vector.sleepMidpoint,
                vector.sleepMidpointVariance7d,
                vector.totalSleepMean7d,
                vector.totalSleepStd7d,
                vector.sleepRegularityIndex,
                vector.interdailyStability7d,
                vector.sleepDurationFirstDifferenceVariance7d,
                vector.circadianPhaseZ,
                vector.activityRhythmAmplitude,
            ] {
                if let v = value {
                    XCTAssertTrue(v.isFinite, "non-finite value \(v)")
                }
            }
        }
    }

    func testProperty_SleepRegularityIndexInUnitInterval() {
        var rng = LCRNG(state: 0x5A1)
        var entries: [MoodEntry] = []
        for d in 1...30 {
            entries.append(entry(
                day: d,
                hour: Int.random(in: 5...11, using: &rng),
                sleep: Double.random(in: 4...10, using: &rng)
            ))
        }
        for vector in CircadianFeatureService.vectors(entries: entries) {
            if let sri = vector.sleepRegularityIndex {
                XCTAssertGreaterThanOrEqual(sri, 0)
                XCTAssertLessThanOrEqual(sri, 100)
            }
        }
    }

    func testInterdailyStabilityIsAlwaysNilUntilMinuteLevelDataLands() {
        // The proxy is documented as always nil until issue #10 Phase 3
        // wires minute-level Apple Watch ingestion. Asserts the contract
        // so a future change that resurrects the degenerate-1.0 path is
        // caught by tests.
        var rng = LCRNG(state: 0x15)
        var entries: [MoodEntry] = []
        for d in 1...30 {
            entries.append(entry(day: d, sleep: Double.random(in: 4...10, using: &rng)))
        }
        for vector in CircadianFeatureService.vectors(entries: entries) {
            XCTAssertNil(vector.interdailyStability7d, "IS must stay nil until Phase 3 minute-level data")
        }
    }
}
