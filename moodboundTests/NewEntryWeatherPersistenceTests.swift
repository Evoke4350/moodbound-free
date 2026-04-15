import XCTest
@testable import moodbound

final class NewEntryWeatherPersistenceTests: XCTestCase {

    func testEditPreservesLegacyPartialWeatherWhenNoNewWeatherAndNotRemoved() {
        let existing = MoodEntry(
            timestamp: Date(),
            moodLevel: 0,
            energy: 3,
            sleepHours: 7,
            irritability: 0,
            anxiety: 0,
            note: "",
            weatherCity: "Portland",
            weatherCode: 61,
            weatherSummary: "Rain",
            temperatureC: nil,
            precipitationMM: nil
        )

        let payload = NewEntryWeatherPersistence.resolve(
            entryToEdit: existing,
            currentWeather: nil,
            weatherExplicitlyRemoved: false
        )

        XCTAssertEqual(payload.city, "Portland")
        XCTAssertEqual(payload.code, 61)
        XCTAssertEqual(payload.summary, "Rain")
        XCTAssertNil(payload.temperatureC)
        XCTAssertNil(payload.precipitationMM)
    }

    func testEditClearWinsWhenExplicitlyRemoved() {
        let existing = MoodEntry(
            timestamp: Date(),
            moodLevel: 0,
            energy: 3,
            sleepHours: 7,
            irritability: 0,
            anxiety: 0,
            note: "",
            weatherCity: "Portland",
            weatherCode: 61,
            weatherSummary: "Rain",
            temperatureC: 10,
            precipitationMM: 2
        )

        let payload = NewEntryWeatherPersistence.resolve(
            entryToEdit: existing,
            currentWeather: nil,
            weatherExplicitlyRemoved: true
        )

        XCTAssertNil(payload.city)
        XCTAssertNil(payload.code)
        XCTAssertNil(payload.summary)
        XCTAssertNil(payload.temperatureC)
        XCTAssertNil(payload.precipitationMM)
    }
}
