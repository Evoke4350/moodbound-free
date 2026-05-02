import XCTest
@testable import moodbound

final class MixedFeaturesGateTests: XCTestCase {
    private let calendar = Calendar(identifier: .gregorian)

    private func entry(
        day: Int,
        mood: Int,
        energy: Int = 3,
        sleep: Double = 7,
        anxiety: Int = 0,
        irritability: Int = 0
    ) -> MoodEntry {
        let date = calendar.date(from: DateComponents(year: 2026, month: 5, day: day, hour: 9))!
        return MoodEntry(
            timestamp: date,
            moodLevel: mood,
            energy: energy,
            sleepHours: sleep,
            irritability: irritability,
            anxiety: anxiety
        )
    }

    func testCalmDaysProduceZeroMixedDays() {
        let entries = (1...10).map { entry(day: $0, mood: 0) }
        XCTAssertEqual(InsightEngine.mixedFeatureDayCount(entries: entries), 0)
    }

    func testAgitatedDepressionCountsAsMixed() {
        let mix = (1...4).map { entry(day: $0, mood: -2, energy: 4) }
        XCTAssertEqual(InsightEngine.mixedFeatureDayCount(entries: mix), 4)
    }

    func testDysphoricActivationCountsAsMixed() {
        let mix = (1...3).map { entry(day: $0, mood: 2, energy: 4, sleep: 4, anxiety: 3) }
        XCTAssertEqual(InsightEngine.mixedFeatureDayCount(entries: mix), 3)
    }

    func testSleepNoiseAloneIsNotMixed() {
        // Variable sleep, balanced mood, no agitation — old formula would
        // have flagged this; new gate must not.
        let entries = [
            entry(day: 1, mood: 0, sleep: 4),
            entry(day: 2, mood: 0, sleep: 11),
            entry(day: 3, mood: 1, sleep: 5),
            entry(day: 4, mood: -1, sleep: 9),
        ]
        XCTAssertEqual(InsightEngine.mixedFeatureDayCount(entries: entries), 0)
    }

    func testSameDayDuplicatesCountOnce() {
        let mix = [
            entry(day: 1, mood: -2, energy: 5),
            entry(day: 1, mood: -2, energy: 5),
            entry(day: 1, mood: -2, energy: 5),
        ]
        XCTAssertEqual(InsightEngine.mixedFeatureDayCount(entries: mix), 1)
    }

    func testUnknownSleepDoesNotTriggerDysphoricActivation() {
        // sleep == 0 is the unknown sentinel; without a real low-sleep
        // value we should not call this dysphoric activation.
        let entries = [
            entry(day: 1, mood: 2, sleep: 0, anxiety: 3),
            entry(day: 2, mood: 2, sleep: 0, anxiety: 3),
        ]
        XCTAssertEqual(InsightEngine.mixedFeatureDayCount(entries: entries), 0)
    }
}
