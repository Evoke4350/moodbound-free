import XCTest
@testable import moodbound

final class OpenMeteoWeatherServiceTests: XCTestCase {

    // MARK: - Weather summary mapping

    func testSummaryClear() {
        XCTAssertEqual(OpenMeteoWeatherService.summary(for: 0), "Clear")
    }

    func testSummaryPartlyCloudy() {
        XCTAssertEqual(OpenMeteoWeatherService.summary(for: 1), "Partly cloudy")
        XCTAssertEqual(OpenMeteoWeatherService.summary(for: 2), "Partly cloudy")
    }

    func testSummaryCloudy() {
        XCTAssertEqual(OpenMeteoWeatherService.summary(for: 3), "Cloudy")
    }

    func testSummaryFog() {
        XCTAssertEqual(OpenMeteoWeatherService.summary(for: 45), "Fog")
        XCTAssertEqual(OpenMeteoWeatherService.summary(for: 48), "Fog")
    }

    func testSummaryDrizzle() {
        for code in [51, 53, 55, 56, 57] {
            XCTAssertEqual(OpenMeteoWeatherService.summary(for: code), "Drizzle", "code \(code)")
        }
    }

    func testSummaryRain() {
        for code in [61, 63, 65, 66, 67, 80, 81, 82] {
            XCTAssertEqual(OpenMeteoWeatherService.summary(for: code), "Rain", "code \(code)")
        }
    }

    func testSummarySnow() {
        for code in [71, 73, 75, 77, 85, 86] {
            XCTAssertEqual(OpenMeteoWeatherService.summary(for: code), "Snow", "code \(code)")
        }
    }

    func testSummaryThunderstorm() {
        for code in [95, 96, 99] {
            XCTAssertEqual(OpenMeteoWeatherService.summary(for: code), "Thunderstorm", "code \(code)")
        }
    }

    func testSummaryUnknownCode() {
        XCTAssertEqual(OpenMeteoWeatherService.summary(for: 999), "Variable")
    }

    // MARK: - Fallback cities

    func testFallbackNewYork() {
        let tz = TimeZone(identifier: "America/New_York")!
        XCTAssertEqual(OpenMeteoWeatherService.fallbackMajorCity(for: tz), "New York")
    }

    func testFallbackLosAngeles() {
        let tz = TimeZone(identifier: "America/Los_Angeles")!
        XCTAssertEqual(OpenMeteoWeatherService.fallbackMajorCity(for: tz), "Los Angeles")
    }

    func testFallbackTokyo() {
        let tz = TimeZone(identifier: "Asia/Tokyo")!
        XCTAssertEqual(OpenMeteoWeatherService.fallbackMajorCity(for: tz), "Tokyo")
    }

    func testFallbackUnknownTimezone() {
        let tz = TimeZone(identifier: "Antarctica/McMurdo")!
        XCTAssertEqual(OpenMeteoWeatherService.fallbackMajorCity(for: tz), "New York")
    }

    func testFallbackLocationHasCoordinates() {
        let tz = TimeZone(identifier: "America/Chicago")!
        let loc = OpenMeteoWeatherService.fallbackMajorLocation(for: tz)
        XCTAssertEqual(loc.city, "Chicago")
        XCTAssertEqual(loc.latitude, 41.8781, accuracy: 0.01)
        XCTAssertEqual(loc.longitude, -87.6298, accuracy: 0.01)
        XCTAssertEqual(loc.timezone, "America/Chicago")
    }

    // MARK: - All fallback locations have valid data

    func testAllFallbackLocationsHaveNonZeroCoordinates() {
        let timezones = [
            "America/Los_Angeles", "America/Denver", "America/Chicago",
            "America/New_York", "Pacific/Honolulu", "America/Anchorage",
            "Europe/London", "Europe/Paris", "Asia/Tokyo", "Asia/Seoul",
            "Asia/Kolkata", "Australia/Sydney"
        ]
        for id in timezones {
            let tz = TimeZone(identifier: id)!
            let loc = OpenMeteoWeatherService.fallbackMajorLocation(for: tz)
            XCTAssertFalse(loc.city.isEmpty, "\(id) has empty city")
            XCTAssertNotEqual(loc.latitude, 0, "\(id) has zero latitude")
            XCTAssertNotEqual(loc.longitude, 0, "\(id) has zero longitude")
            XCTAssertFalse(loc.timezone.isEmpty, "\(id) has empty timezone")
        }
    }
}
