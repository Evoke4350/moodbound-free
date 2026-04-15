import Foundation

struct WeatherLocation: Equatable {
    let city: String
    let latitude: Double
    let longitude: Double
    let timezone: String
}

struct DailyWeather {
    let date: Date
    let weatherCode: Int
    let temperatureC: Double
    let precipitationMM: Double
}

enum OpenMeteoWeatherService {
    enum WeatherError: LocalizedError {
        case invalidURL
        case noLocationFound
        case invalidResponse

        var errorDescription: String? {
            switch self {
            case .invalidURL:
                return "Failed to build weather request URL."
            case .noLocationFound:
                return "Couldn’t find a city match."
            case .invalidResponse:
                return "Weather provider returned an invalid response."
            }
        }
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private struct GeocodingResponse: Decodable {
        struct Result: Decodable {
            let name: String
            let latitude: Double
            let longitude: Double
            let timezone: String
            let admin1: String?
            let country: String?
        }
        let results: [Result]?
    }

    private struct ArchiveResponse: Decodable {
        struct Daily: Decodable {
            let time: [String]
            let weathercode: [Int]
            let temperature_2m_max: [Double]
            let temperature_2m_min: [Double]
            let precipitation_sum: [Double]
        }
        let daily: Daily?
    }

    static func geocodeCity(_ name: String) async throws -> WeatherLocation {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw WeatherError.noLocationFound }
        guard let query = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://geocoding-api.open-meteo.com/v1/search?name=\(query)&count=1&language=en&format=json") else {
            throw WeatherError.invalidURL
        }

        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw WeatherError.invalidResponse
        }

        let decoded = try JSONDecoder().decode(GeocodingResponse.self, from: data)
        guard let top = decoded.results?.first else {
            throw WeatherError.noLocationFound
        }

        let city = [top.name, top.admin1, top.country]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
        return WeatherLocation(
            city: city,
            latitude: top.latitude,
            longitude: top.longitude,
            timezone: top.timezone
        )
    }

    static func fallbackMajorCity(for timeZone: TimeZone) -> String {
        switch timeZone.identifier {
        case "America/Los_Angeles": return "Los Angeles"
        case "America/Denver": return "Denver"
        case "America/Chicago": return "Chicago"
        case "America/New_York": return "New York"
        case "America/Phoenix": return "Phoenix"
        case "America/Anchorage": return "Anchorage"
        case "Pacific/Honolulu": return "Honolulu"
        case "Europe/London": return "London"
        case "Europe/Paris", "Europe/Berlin": return "Berlin"
        case "Asia/Tokyo": return "Tokyo"
        case "Asia/Seoul": return "Seoul"
        case "Asia/Kolkata": return "Mumbai"
        case "Australia/Sydney": return "Sydney"
        default:
            return "New York"
        }
    }

    static func fallbackMajorLocation(for timeZone: TimeZone) -> WeatherLocation {
        switch timeZone.identifier {
        case "America/Los_Angeles":
            return WeatherLocation(city: "Los Angeles", latitude: 34.0522, longitude: -118.2437, timezone: "America/Los_Angeles")
        case "America/Denver":
            return WeatherLocation(city: "Denver", latitude: 39.7392, longitude: -104.9903, timezone: "America/Denver")
        case "America/Chicago":
            return WeatherLocation(city: "Chicago", latitude: 41.8781, longitude: -87.6298, timezone: "America/Chicago")
        case "America/New_York":
            return WeatherLocation(city: "New York", latitude: 40.7128, longitude: -74.0060, timezone: "America/New_York")
        case "Pacific/Honolulu":
            return WeatherLocation(city: "Honolulu", latitude: 21.3069, longitude: -157.8583, timezone: "Pacific/Honolulu")
        case "America/Anchorage":
            return WeatherLocation(city: "Anchorage", latitude: 61.2181, longitude: -149.9003, timezone: "America/Anchorage")
        case "Europe/London":
            return WeatherLocation(city: "London", latitude: 51.5072, longitude: -0.1276, timezone: "Europe/London")
        case "Europe/Paris", "Europe/Berlin":
            return WeatherLocation(city: "Berlin", latitude: 52.5200, longitude: 13.4050, timezone: "Europe/Berlin")
        case "Asia/Tokyo":
            return WeatherLocation(city: "Tokyo", latitude: 35.6762, longitude: 139.6503, timezone: "Asia/Tokyo")
        case "Asia/Seoul":
            return WeatherLocation(city: "Seoul", latitude: 37.5665, longitude: 126.9780, timezone: "Asia/Seoul")
        case "Asia/Kolkata":
            return WeatherLocation(city: "Mumbai", latitude: 19.0760, longitude: 72.8777, timezone: "Asia/Kolkata")
        case "Australia/Sydney":
            return WeatherLocation(city: "Sydney", latitude: -33.8688, longitude: 151.2093, timezone: "Australia/Sydney")
        default:
            return WeatherLocation(city: "New York", latitude: 40.7128, longitude: -74.0060, timezone: "America/New_York")
        }
    }

    static func fetchHistoricalDaily(
        location: WeatherLocation,
        startDate: Date,
        endDate: Date
    ) async throws -> [Date: DailyWeather] {
        let start = dayFormatter.string(from: startDate)
        let end = dayFormatter.string(from: endDate)

        guard let url = URL(
            string: "https://archive-api.open-meteo.com/v1/archive?latitude=\(location.latitude)&longitude=\(location.longitude)&start_date=\(start)&end_date=\(end)&daily=weathercode,temperature_2m_max,temperature_2m_min,precipitation_sum&timezone=\(location.timezone.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "auto")"
        ) else {
            throw WeatherError.invalidURL
        }

        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw WeatherError.invalidResponse
        }

        let decoded = try JSONDecoder().decode(ArchiveResponse.self, from: data)
        guard let daily = decoded.daily else { throw WeatherError.invalidResponse }

        var result: [Date: DailyWeather] = [:]
        for index in daily.time.indices {
            guard let day = dayFormatter.date(from: daily.time[index]) else { continue }
            let maxT = daily.temperature_2m_max[safe: index] ?? 0
            let minT = daily.temperature_2m_min[safe: index] ?? 0
            let avgT = (maxT + minT) / 2.0
            let precip = daily.precipitation_sum[safe: index] ?? 0
            let code = daily.weathercode[safe: index] ?? 0
            result[day] = DailyWeather(
                date: day,
                weatherCode: code,
                temperatureC: avgT,
                precipitationMM: precip
            )
        }
        return result
    }

    struct CurrentWeather {
        let city: String
        let weatherCode: Int
        let temperatureC: Double
        let precipitationMM: Double
        let summary: String
    }

    private struct ForecastResponse: Decodable {
        struct Current: Decodable {
            let temperature_2m: Double
            let weather_code: Int
            let precipitation: Double
        }
        let current: Current?
    }

    static func fetchCurrentWeather(location: WeatherLocation) async throws -> CurrentWeather {
        guard let url = URL(
            string: "https://api.open-meteo.com/v1/forecast?latitude=\(location.latitude)&longitude=\(location.longitude)&current=temperature_2m,weather_code,precipitation&timezone=\(location.timezone.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "auto")"
        ) else {
            throw WeatherError.invalidURL
        }

        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw WeatherError.invalidResponse
        }

        let decoded = try JSONDecoder().decode(ForecastResponse.self, from: data)
        guard let current = decoded.current else { throw WeatherError.invalidResponse }

        return CurrentWeather(
            city: location.city,
            weatherCode: current.weather_code,
            temperatureC: current.temperature_2m,
            precipitationMM: current.precipitation,
            summary: summary(for: current.weather_code)
        )
    }

    static func fetchCurrentWeatherForLocation(latitude: Double, longitude: Double, city: String, timezone: String) async throws -> CurrentWeather {
        let location = WeatherLocation(city: city, latitude: latitude, longitude: longitude, timezone: timezone)
        return try await fetchCurrentWeather(location: location)
    }

    static func summary(for code: Int) -> String {
        switch code {
        case 0: return "Clear"
        case 1, 2: return "Partly cloudy"
        case 3: return "Cloudy"
        case 45, 48: return "Fog"
        case 51, 53, 55, 56, 57: return "Drizzle"
        case 61, 63, 65, 66, 67, 80, 81, 82: return "Rain"
        case 71, 73, 75, 77, 85, 86: return "Snow"
        case 95, 96, 99: return "Thunderstorm"
        default: return "Variable"
        }
    }
}

private extension Array {
    subscript(safe index: Index) -> Element? {
        guard indices.contains(index) else { return nil }
        return self[index]
    }
}
