import XCTest
@testable import moodbound

final class LifeChartServiceTests: XCTestCase {
    private let calendar = Calendar(identifier: .gregorian)

    private func date(_ d: Int, hour: Int = 9) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 5, day: d, hour: hour))!
    }

    private func entry(
        day: Int,
        hour: Int = 9,
        mood: Int,
        energy: Int = 3,
        sleep: Double = 7,
        anxiety: Int = 0,
        irritability: Int = 0
    ) -> MoodEntry {
        MoodEntry(
            timestamp: date(day, hour: hour),
            moodLevel: mood,
            energy: energy,
            sleepHours: sleep,
            irritability: irritability,
            anxiety: anxiety
        )
    }

    // MARK: - LifeChartBand

    func testBandMappingCoversAllMoodLevels() {
        XCTAssertEqual(LifeChartBand(moodLevel: -3), .severeDepression)
        XCTAssertEqual(LifeChartBand(moodLevel: -2), .moderateHighDepression)
        XCTAssertEqual(LifeChartBand(moodLevel: -1), .moderateLowDepression)
        XCTAssertEqual(LifeChartBand(moodLevel: 0), .euthymic)
        XCTAssertEqual(LifeChartBand(moodLevel: 1), .moderateLowElevation)
        XCTAssertEqual(LifeChartBand(moodLevel: 2), .moderateHighElevation)
        XCTAssertEqual(LifeChartBand(moodLevel: 3), .severeMania)
    }

    func testBarWeightIsPropertyOfBand() {
        XCTAssertEqual(LifeChartBand.severeMania.barWeight, 1.0)
        XCTAssertEqual(LifeChartBand.moderateHighDepression.barWeight, 0.75)
        XCTAssertEqual(LifeChartBand.moderateLowElevation.barWeight, 0.5)
        XCTAssertEqual(LifeChartBand.euthymic.barWeight, 0)
    }

    // MARK: - WorstOfDayReducer

    func testWorstOfDayReducerPicksMaxAbsoluteMood() {
        let entries = [
            entry(day: 1, hour: 8, mood: 0),
            entry(day: 1, hour: 12, mood: -2),
            entry(day: 1, hour: 18, mood: 1),
        ]
        let band = WorstOfDayReducer().reduce(entries: entries)
        XCTAssertEqual(band, .moderateHighDepression)
    }

    func testWorstOfDayReducerReturnsNilForEmpty() {
        XCTAssertNil(WorstOfDayReducer().reduce(entries: []))
    }

    func testWorstOfDayReducerBreaksTiesByLatestEntry() {
        let entries = [
            entry(day: 1, hour: 8, mood: -2),
            entry(day: 1, hour: 18, mood: 2),
        ]
        let band = WorstOfDayReducer().reduce(entries: entries)
        XCTAssertEqual(band, .moderateHighElevation)
    }

    // MARK: - LifeChartService

    func testBuildEmitsBarPerDayInWindow() {
        let entries = [entry(day: 5, mood: -2)]
        let data = LifeChartService.build(
            entries: entries,
            window: .days(7),
            now: date(7, hour: 18),
            calendar: calendar
        )
        XCTAssertEqual(data.bars.count, 7)
        XCTAssertTrue(data.bars.contains { $0.day == calendar.startOfDay(for: date(5)) && $0.band == .moderateHighDepression })
        XCTAssertTrue(data.bars.contains { $0.day == calendar.startOfDay(for: date(1)) && $0.band == nil })
    }

    func testMixedFeatureFlagPropagatesToDayBar() {
        let entries = [entry(day: 3, mood: -2, energy: 5)]
        let data = LifeChartService.build(
            entries: entries,
            window: .days(7),
            now: date(7),
            calendar: calendar
        )
        let bar = data.bars.first { $0.day == calendar.startOfDay(for: date(3)) }
        XCTAssertEqual(bar?.isMixedFeatures, true)
    }

    func testAllWindowSpansEarliestEntryToToday() {
        let entries = [
            entry(day: 1, mood: 0),
            entry(day: 5, mood: 0),
        ]
        let data = LifeChartService.build(
            entries: entries,
            window: .all,
            now: date(7),
            calendar: calendar
        )
        XCTAssertEqual(data.bars.count, 7)
    }

    // MARK: - Annotation providers

    func testHighIntensityTriggerProviderEmitsForIntensity3Only() {
        let trigger = TriggerFactor(name: "Stress")
        let e = entry(day: 4, mood: 0)
        e.triggerEvents = [
            TriggerEvent(timestamp: e.timestamp, intensity: 2, trigger: trigger, moodEntry: e),
            TriggerEvent(timestamp: e.timestamp, intensity: 3, trigger: trigger, moodEntry: e),
        ]
        let provider = HighIntensityTriggerProvider()
        let window = DateInterval(start: date(1), end: date(8))
        let annotations = provider.annotations(entries: [e], window: window, calendar: calendar)
        XCTAssertEqual(annotations.count, 1)
        if case .highIntensityTrigger(let name, let intensity, _) = annotations[0] {
            XCTAssertEqual(name, "Stress")
            XCTAssertEqual(intensity, 3)
        } else {
            XCTFail("Expected highIntensityTrigger annotation")
        }
    }

    func testMedicationChangeProviderEmitsStartOnFirstAppearance() {
        let med = Medication(name: "Lithium")
        let e1 = entry(day: 3, mood: 0)
        let e2 = entry(day: 5, mood: 0)
        e1.medicationAdherenceEvents = [
            MedicationAdherenceEvent(timestamp: e1.timestamp, taken: true, medication: med, moodEntry: e1)
        ]
        e2.medicationAdherenceEvents = [
            MedicationAdherenceEvent(timestamp: e2.timestamp, taken: true, medication: med, moodEntry: e2)
        ]
        let provider = MedicationChangeProvider(gracePeriodDays: 14)
        let window = DateInterval(start: date(1), end: date(8))
        let annotations = provider.annotations(entries: [e1, e2], window: window, calendar: calendar)
        XCTAssertEqual(annotations.count, 1)
        if case .medicationStarted(let name, let day) = annotations[0] {
            XCTAssertEqual(name, "Lithium")
            XCTAssertEqual(day, calendar.startOfDay(for: date(3)))
        } else {
            XCTFail("Expected medicationStarted annotation")
        }
    }

    func testMedicationChangeProviderEmitsStopWhenSilentBeyondGracePeriod() {
        let med = Medication(name: "Lithium")
        let e1 = entry(day: 1, mood: 0)
        e1.medicationAdherenceEvents = [
            MedicationAdherenceEvent(timestamp: e1.timestamp, taken: true, medication: med, moodEntry: e1)
        ]
        let provider = MedicationChangeProvider(gracePeriodDays: 5)
        let window = DateInterval(start: date(1), end: date(20))
        let annotations = provider.annotations(entries: [e1], window: window, calendar: calendar)
        XCTAssertTrue(annotations.contains { ann in
            if case .medicationStopped(let name, _) = ann { return name == "Lithium" }
            return false
        })
    }

    // MARK: - Strategy injection

    func testCustomReducerOverridesDefault() {
        struct AlwaysSevereReducer: LifeChartDayReducer {
            func reduce(entries: [MoodEntry]) -> LifeChartBand? {
                entries.isEmpty ? nil : .severeMania
            }
        }
        let entries = [entry(day: 3, mood: 0)]
        let data = LifeChartService.build(
            entries: entries,
            window: .days(7),
            now: date(7),
            calendar: calendar,
            reducer: AlwaysSevereReducer(),
            annotationProviders: []
        )
        let bar = data.bars.first { $0.day == calendar.startOfDay(for: date(3)) }
        XCTAssertEqual(bar?.band, .severeMania)
    }
}
