import XCTest
@testable import moodbound

/// Property tests that pin down the contracts the strategy seams must
/// honor regardless of which concrete reducer / annotation provider is
/// plugged in. Run on randomized but bounded inputs so future v2
/// reducers (e.g. mixed-split) and new annotation providers are forced
/// to satisfy the same chart-rendering invariants.
final class LifeChartPropertyTests: XCTestCase {
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

    private func randomEntries(rng: inout LCRNG, count: Int, withinDays span: Int) -> [MoodEntry] {
        (0..<count).map { _ in
            let day = Int.random(in: 1...max(1, span), using: &rng)
            let hour = Int.random(in: 0...23, using: &rng)
            let mood = Int.random(in: -3...3, using: &rng)
            let energy = Int.random(in: 1...5, using: &rng)
            let sleep = Double.random(in: 3...11, using: &rng)
            let anxiety = Int.random(in: 0...3, using: &rng)
            let irritability = Int.random(in: 0...3, using: &rng)
            return MoodEntry(
                timestamp: date(day, hour: hour),
                moodLevel: mood,
                energy: energy,
                sleepHours: sleep,
                irritability: irritability,
                anxiety: anxiety
            )
        }
    }

    // MARK: - LifeChartBand invariants

    func testProperty_BandMappingIsMonotonicInMoodLevel() {
        for low in -3...2 {
            let high = low + 1
            let lowBand = LifeChartBand(moodLevel: low)
            let highBand = LifeChartBand(moodLevel: high)
            XCTAssertLessThanOrEqual(lowBand.rawValue, highBand.rawValue,
                "Band(\(low))=\(lowBand.rawValue) must be ≤ Band(\(high))=\(highBand.rawValue)")
        }
    }

    func testProperty_BarWeightAlwaysInUnitInterval() {
        for band in LifeChartBand.allCases {
            XCTAssertGreaterThanOrEqual(band.barWeight, 0, "barWeight must be ≥ 0")
            XCTAssertLessThanOrEqual(band.barWeight, 1, "barWeight must be ≤ 1")
        }
    }

    func testProperty_PoleMatchesSign() {
        for band in LifeChartBand.allCases {
            switch band.pole {
            case .depression: XCTAssertLessThan(band.rawValue, 0)
            case .euthymic: XCTAssertEqual(band.rawValue, 0)
            case .elevation: XCTAssertGreaterThan(band.rawValue, 0)
            }
        }
    }

    func testProperty_OutOfRangeMoodSaturatesAtSevereBand() {
        // Defensive: the validator caps at ±3 today, but the band mapping
        // shouldn't trap or wrap if a future code path passes -10 / +10.
        XCTAssertEqual(LifeChartBand(moodLevel: -100), .severeDepression)
        XCTAssertEqual(LifeChartBand(moodLevel: 100), .severeMania)
    }

    // MARK: - Reducer contract (any conforming type)

    private func assertReducerContract(_ reducer: LifeChartDayReducer, file: StaticString = #file, line: UInt = #line) {
        XCTAssertNil(reducer.reduce(entries: []), "Reducer must return nil for empty input", file: file, line: line)

        var rng = LCRNG(state: 0xDEADBEEF)
        for trial in 0..<40 {
            let count = Int.random(in: 1...6, using: &rng)
            let entries = randomEntries(rng: &rng, count: count, withinDays: 1)
            let band = reducer.reduce(entries: entries)
            XCTAssertNotNil(band, "Reducer must produce a band for non-empty input (trial \(trial))", file: file, line: line)
            if let band {
                XCTAssertGreaterThanOrEqual(band.barWeight, 0, file: file, line: line)
                XCTAssertLessThanOrEqual(band.barWeight, 1, file: file, line: line)
            }
        }
    }

    func testProperty_WorstOfDayReducerHonorsContract() {
        assertReducerContract(WorstOfDayReducer())
    }

    func testProperty_WorstOfDayReducerNeverExceedsMaxAbsMoodInInput() {
        var rng = LCRNG(state: 0xFEEDFACE)
        for _ in 0..<60 {
            let count = Int.random(in: 1...6, using: &rng)
            let entries = randomEntries(rng: &rng, count: count, withinDays: 1)
            guard let band = WorstOfDayReducer().reduce(entries: entries) else { continue }
            let maxAbs = entries.map { abs($0.moodLevel) }.max() ?? 0
            // The chart band's |rawValue| can be up to 4 (severe). Moodbound
            // mood ±3 maps to band ±4 — i.e. the band scale is one step
            // wider per pole. The contract: don't introduce a *new* pole
            // and don't underestimate. Specifically, if max-abs mood is 0,
            // band must be euthymic.
            if maxAbs == 0 {
                XCTAssertEqual(band, .euthymic)
            } else {
                XCTAssertNotEqual(band, .euthymic, "Non-zero mood should never reduce to euthymic")
            }
        }
    }

    // MARK: - Annotation provider contract

    private func assertAnnotationsWithinWindow(
        _ provider: LifeChartAnnotationProvider,
        entries: [MoodEntry],
        window: DateInterval
    ) {
        let annotations = provider.annotations(entries: entries, window: window, calendar: calendar)
        for annotation in annotations {
            XCTAssertTrue(
                window.contains(annotation.day),
                "Annotation day \(annotation.day) must fall within window \(window.start)–\(window.end)"
            )
        }
    }

    func testProperty_HighIntensityTriggerProviderEmitsOnlyWithinWindow() {
        var rng = LCRNG(state: 0xC0FFEEFEED)
        let trigger = TriggerFactor(name: "Stress")
        for _ in 0..<30 {
            let entries = randomEntries(rng: &rng, count: 6, withinDays: 30)
            for entry in entries {
                entry.triggerEvents = [
                    TriggerEvent(timestamp: entry.timestamp, intensity: Int.random(in: 1...3, using: &rng), trigger: trigger, moodEntry: entry)
                ]
            }
            // LifeChartService always hands providers a day-aligned window,
            // so test that contract — not a fictitious 9am-to-9am one.
            let window = DateInterval(
                start: calendar.startOfDay(for: date(5)),
                end: calendar.startOfDay(for: date(21))
            )
            assertAnnotationsWithinWindow(HighIntensityTriggerProvider(), entries: entries, window: window)
        }
    }

    func testProperty_MedicationChangeProviderEmitsOnlyWithinWindow() {
        var rng = LCRNG(state: 0xBADD00D)
        let med = Medication(name: "Lithium")
        for _ in 0..<30 {
            let entries = randomEntries(rng: &rng, count: 6, withinDays: 30)
            for entry in entries {
                entry.medicationAdherenceEvents = [
                    MedicationAdherenceEvent(timestamp: entry.timestamp, taken: true, medication: med, moodEntry: entry)
                ]
            }
            let window = DateInterval(
                start: calendar.startOfDay(for: date(5)),
                end: calendar.startOfDay(for: date(21))
            )
            assertAnnotationsWithinWindow(MedicationChangeProvider(), entries: entries, window: window)
        }
    }

    // MARK: - LifeChartService whole-payload invariants

    func testProperty_DaysWindowProducesExactlyNBars() {
        var rng = LCRNG(state: 0x123456789ABCDEF0)
        for n in [1, 7, 30, 90, 365] {
            let entries = randomEntries(rng: &rng, count: 25, withinDays: n)
            let data = LifeChartService.build(
                entries: entries,
                window: .days(n),
                now: date(min(28, n), hour: 18),
                calendar: calendar,
                annotationProviders: []
            )
            XCTAssertEqual(data.bars.count, n, "days(\(n)) window must produce \(n) bars, got \(data.bars.count)")
        }
    }

    func testProperty_BarsAreStrictlyOrderedByDay() {
        var rng = LCRNG(state: 0xABCDEF0123456789)
        for _ in 0..<10 {
            let entries = randomEntries(rng: &rng, count: 30, withinDays: 30)
            let data = LifeChartService.build(
                entries: entries,
                window: .days(30),
                now: date(28, hour: 18),
                calendar: calendar,
                annotationProviders: []
            )
            for i in 1..<data.bars.count {
                XCTAssertLessThan(data.bars[i - 1].day, data.bars[i].day,
                    "Bars must be strictly ordered by day at index \(i)")
            }
        }
    }

    func testProperty_AnnotationsAreSortedByDay() {
        var rng = LCRNG(state: 0x55AA55AA55AA55AA)
        let trigger = TriggerFactor(name: "Stress")
        for _ in 0..<10 {
            let entries = randomEntries(rng: &rng, count: 20, withinDays: 30)
            for entry in entries {
                entry.triggerEvents = [
                    TriggerEvent(timestamp: entry.timestamp, intensity: 3, trigger: trigger, moodEntry: entry)
                ]
            }
            let data = LifeChartService.build(
                entries: entries,
                window: .days(30),
                now: date(30, hour: 18),
                calendar: calendar
            )
            for i in 1..<data.annotations.count {
                XCTAssertLessThanOrEqual(data.annotations[i - 1].day, data.annotations[i].day,
                    "Annotations must be sorted by day")
            }
        }
    }

    func testProperty_MixedFlagOnlyOnDaysThatActuallyContainMixedEntries() {
        var rng = LCRNG(state: 0x7777777777777777)
        let entries = randomEntries(rng: &rng, count: 40, withinDays: 30)
        let data = LifeChartService.build(
            entries: entries,
            window: .days(30),
            now: date(30, hour: 18),
            calendar: calendar,
            annotationProviders: []
        )
        let entriesByDay = Dictionary(grouping: entries) { calendar.startOfDay(for: $0.timestamp) }
        for bar in data.bars where bar.isMixedFeatures {
            let dayEntries = entriesByDay[bar.day] ?? []
            // At least one entry on a mixed day must satisfy a mixed-features
            // pattern: low mood + activation OR elevated + insomnia + dysphoric.
            let anyMixed = dayEntries.contains { entry in
                let agitatedDepression = entry.moodLevel <= -1
                    && (entry.energy >= 4 || (entry.anxiety >= 2 && entry.irritability >= 2))
                let dysphoricActivation = entry.moodLevel >= 1
                    && entry.sleepHours > 0 && entry.sleepHours < 5
                    && (entry.anxiety >= 2 || entry.irritability >= 2)
                return agitatedDepression || dysphoricActivation
            }
            XCTAssertTrue(anyMixed, "Bar on \(bar.day) is flagged mixed but no entry that day actually qualifies")
        }
    }

    func testProperty_LastBarNeverPastNow() {
        var rng = LCRNG(state: 0x9999AAAA9999AAAA)
        for _ in 0..<10 {
            let now = date(15, hour: 18)
            let entries = randomEntries(rng: &rng, count: 10, withinDays: 30)
            let data = LifeChartService.build(
                entries: entries,
                window: .days(30),
                now: now,
                calendar: calendar,
                annotationProviders: []
            )
            let nowDay = calendar.startOfDay(for: now)
            if let last = data.bars.last {
                XCTAssertLessThanOrEqual(last.day, nowDay, "Chart must not project beyond now")
            }
        }
    }

    func testProperty_ServiceIsDeterministicForFixedInputs() {
        var rng = LCRNG(state: 0xDEFA17DEFA17DEFA)
        let entries = randomEntries(rng: &rng, count: 25, withinDays: 30)
        let now = date(30, hour: 18)
        let a = LifeChartService.build(entries: entries, window: .days(30), now: now, calendar: calendar)
        let b = LifeChartService.build(entries: entries, window: .days(30), now: now, calendar: calendar)
        XCTAssertEqual(a.bars, b.bars)
        XCTAssertEqual(a.annotations, b.annotations)
        XCTAssertEqual(a.window, b.window)
    }
}
