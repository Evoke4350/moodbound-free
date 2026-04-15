import Foundation
import WeatherKit
import CoreLocation

enum WeatherKitWeatherService {
    enum WeatherError: LocalizedError {
        case unavailable

        var errorDescription: String? {
            "Weather data unavailable."
        }
    }

    struct CurrentWeather {
        let city: String
        let weatherCode: Int
        let temperatureC: Double
        let precipitationMM: Double
        let summary: String
    }

    static func fetchCurrentWeather(for location: CLLocation, city: String) async throws -> CurrentWeather {
        let weather = try await WeatherService.shared.weather(
            for: location,
            including: .current, .daily
        )

        let current = weather.0
        let daily = weather.1

        let code = mapConditionToWMOCode(current.condition)
        let summary = summaryText(for: current.condition)
        let tempC = current.temperature.converted(to: .celsius).value

        let precipMM: Double
        if let today = daily.first {
            precipMM = today.precipitationAmount.converted(to: .millimeters).value
        } else {
            precipMM = 0
        }

        return CurrentWeather(
            city: city,
            weatherCode: code,
            temperatureC: tempC,
            precipitationMM: precipMM,
            summary: summary
        )
    }

    private static func mapConditionToWMOCode(_ condition: WeatherCondition) -> Int {
        switch condition {
        case .clear, .hot:
            return 0
        case .mostlyClear:
            return 1
        case .partlyCloudy, .breezy, .windy:
            return 2
        case .mostlyCloudy, .cloudy:
            return 3
        case .foggy, .haze, .smoky, .blowingDust:
            return 45
        case .drizzle, .sunShowers:
            return 51
        case .freezingDrizzle:
            return 56
        case .rain:
            return 61
        case .heavyRain:
            return 65
        case .freezingRain:
            return 66
        case .snow, .flurries, .blowingSnow, .sunFlurries:
            return 71
        case .heavySnow, .blizzard:
            return 75
        case .sleet, .wintryMix:
            // WMO 67: rain & snow / ice pellets — sleet is icy rain, not snow grains (77).
            return 67
        case .hail:
            // WMO 96: thunderstorm with slight hail.
            return 96
        case .thunderstorms, .isolatedThunderstorms, .scatteredThunderstorms,
             .strongStorms, .tropicalStorm, .hurricane:
            return 95
        case .frigid:
            return 0
        @unknown default:
            return 0
        }
    }

    private static func summaryText(for condition: WeatherCondition) -> String {
        switch condition {
        case .clear, .hot, .mostlyClear:
            return "Clear"
        case .partlyCloudy, .breezy, .windy:
            return "Partly cloudy"
        case .mostlyCloudy, .cloudy:
            return "Cloudy"
        case .foggy, .haze, .smoky, .blowingDust:
            return "Fog"
        case .drizzle, .freezingDrizzle, .sunShowers:
            return "Drizzle"
        case .rain, .heavyRain, .freezingRain:
            return "Rain"
        case .snow, .heavySnow, .flurries, .blizzard, .blowingSnow, .sunFlurries:
            return "Snow"
        case .sleet, .wintryMix:
            return "Sleet"
        case .hail:
            return "Hail"
        case .thunderstorms, .isolatedThunderstorms, .scatteredThunderstorms,
             .strongStorms, .tropicalStorm, .hurricane:
            return "Thunderstorm"
        case .frigid:
            return "Clear"
        @unknown default:
            return "Variable"
        }
    }
}
