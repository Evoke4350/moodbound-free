import Foundation

enum NewEntryWeatherPersistence {
    struct Payload {
        let city: String?
        let code: Int?
        let summary: String?
        let temperatureC: Double?
        let precipitationMM: Double?
    }

    static func resolve(
        entryToEdit: MoodEntry?,
        currentWeather: OpenMeteoWeatherService.CurrentWeather?,
        weatherExplicitlyRemoved: Bool
    ) -> Payload {
        if let currentWeather {
            return Payload(
                city: nilIfEmpty(currentWeather.city),
                code: currentWeather.weatherCode,
                summary: nilIfEmpty(currentWeather.summary),
                temperatureC: currentWeather.temperatureC,
                precipitationMM: currentWeather.precipitationMM
            )
        }

        if weatherExplicitlyRemoved {
            return Payload(city: nil, code: nil, summary: nil, temperatureC: nil, precipitationMM: nil)
        }

        if let entryToEdit {
            return Payload(
                city: nilIfEmpty(entryToEdit.weatherCity),
                code: entryToEdit.weatherCode,
                summary: nilIfEmpty(entryToEdit.weatherSummary),
                temperatureC: entryToEdit.temperatureC,
                precipitationMM: entryToEdit.precipitationMM
            )
        }

        return Payload(city: nil, code: nil, summary: nil, temperatureC: nil, precipitationMM: nil)
    }

    private static func nilIfEmpty(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value
    }
}
