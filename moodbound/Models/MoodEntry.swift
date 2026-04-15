import Foundation
import SwiftData

@Model
final class MoodEntry {
    var timestamp: Date
    var moodLevel: Int // -3 (deep depression) to +3 (severe mania)
    var energy: Int // 1-5
    var sleepHours: Double
    var irritability: Int // 0-3
    var anxiety: Int // 0-3
    var note: String
    var weatherCity: String?
    var weatherCode: Int?
    var weatherSummary: String?
    var temperatureC: Double?
    var precipitationMM: Double?
    var restingHeartRate: Double?
    var hrvSDNN: Double?
    var stepCount: Int?
    var mindfulMinutes: Double?
    @Relationship(deleteRule: .cascade, inverse: \MedicationAdherenceEvent.moodEntry)
    var medicationAdherenceEvents: [MedicationAdherenceEvent]
    @Relationship(deleteRule: .cascade, inverse: \TriggerEvent.moodEntry)
    var triggerEvents: [TriggerEvent]

    var mood: MoodScale {
        MoodScale(rawValue: moodLevel) ?? .balanced
    }

    var moodLabel: String {
        mood.label
    }

    var moodColor: String {
        String(describing: mood.color)
    }

    var moodEmoji: String {
        mood.emoji
    }

    var weatherEmoji: String? {
        guard let code = weatherCode else { return nil }
        switch code {
        case 0: return "☀️"
        case 1, 2: return "🌤️"
        case 3: return "☁️"
        case 45, 48: return "🌫️"
        case 51, 53, 55, 56, 57: return "🌦️"
        case 61, 63, 65, 66, 67, 80, 81, 82: return "🌧️"
        case 71, 73, 75, 77, 85, 86: return "❄️"
        case 95, 96, 99: return "⛈️"
        default: return "🌡️"
        }
    }

    var medicationNames: [String] {
        let names = medicationAdherenceEvents.compactMap { $0.medication?.name }
        var seen = Set<String>()
        var ordered: [String] = []
        for name in names {
            let key = name.lowercased()
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            ordered.append(name)
        }
        return ordered
    }

    init(
        timestamp: Date = .now,
        moodLevel: Int = 0,
        energy: Int = 3,
        sleepHours: Double = 7,
        irritability: Int = 0,
        anxiety: Int = 0,
        note: String = "",
        weatherCity: String? = nil,
        weatherCode: Int? = nil,
        weatherSummary: String? = nil,
        temperatureC: Double? = nil,
        precipitationMM: Double? = nil,
        restingHeartRate: Double? = nil,
        hrvSDNN: Double? = nil,
        stepCount: Int? = nil,
        mindfulMinutes: Double? = nil
    ) {
        self.timestamp = timestamp
        self.moodLevel = moodLevel
        self.energy = energy
        self.sleepHours = sleepHours
        self.irritability = irritability
        self.anxiety = anxiety
        self.note = note
        self.weatherCity = weatherCity
        self.weatherCode = weatherCode
        self.weatherSummary = weatherSummary
        self.temperatureC = temperatureC
        self.precipitationMM = precipitationMM
        self.restingHeartRate = restingHeartRate
        self.hrvSDNN = hrvSDNN
        self.stepCount = stepCount
        self.mindfulMinutes = mindfulMinutes
        self.medicationAdherenceEvents = []
        self.triggerEvents = []
    }

    static func makeValidated(
        timestamp: Date,
        moodLevel: Int,
        energy: Int,
        sleepHours: Double,
        irritability: Int,
        anxiety: Int,
        note: String,
        weatherCity: String? = nil,
        weatherCode: Int? = nil,
        weatherSummary: String? = nil,
        temperatureC: Double? = nil,
        precipitationMM: Double? = nil,
        restingHeartRate: Double? = nil,
        hrvSDNN: Double? = nil,
        stepCount: Int? = nil,
        mindfulMinutes: Double? = nil
    ) throws -> MoodEntry {
        try MoodEntryValidator.validate(
            moodLevel: moodLevel,
            energy: energy,
            sleepHours: sleepHours,
            irritability: irritability,
            anxiety: anxiety,
            note: note
        )

        return MoodEntry(
            timestamp: timestamp,
            moodLevel: moodLevel,
            energy: energy,
            sleepHours: sleepHours,
            irritability: irritability,
            anxiety: anxiety,
            note: note,
            weatherCity: weatherCity,
            weatherCode: weatherCode,
            weatherSummary: weatherSummary,
            temperatureC: temperatureC,
            precipitationMM: precipitationMM,
            restingHeartRate: restingHeartRate,
            hrvSDNN: hrvSDNN,
            stepCount: stepCount,
            mindfulMinutes: mindfulMinutes
        )
    }

    func applyValidatedUpdate(
        timestamp: Date,
        moodLevel: Int,
        energy: Int,
        sleepHours: Double,
        irritability: Int,
        anxiety: Int,
        note: String,
        weatherCity: String? = nil,
        weatherCode: Int? = nil,
        weatherSummary: String? = nil,
        temperatureC: Double? = nil,
        precipitationMM: Double? = nil,
        restingHeartRate: Double? = nil,
        hrvSDNN: Double? = nil,
        stepCount: Int? = nil,
        mindfulMinutes: Double? = nil
    ) throws {
        try MoodEntryValidator.validate(
            moodLevel: moodLevel,
            energy: energy,
            sleepHours: sleepHours,
            irritability: irritability,
            anxiety: anxiety,
            note: note
        )

        self.timestamp = timestamp
        self.moodLevel = moodLevel
        self.energy = energy
        self.sleepHours = sleepHours
        self.irritability = irritability
        self.anxiety = anxiety
        self.note = note
        self.weatherCity = weatherCity
        self.weatherCode = weatherCode
        self.weatherSummary = weatherSummary
        self.temperatureC = temperatureC
        self.precipitationMM = precipitationMM
        self.restingHeartRate = restingHeartRate
        self.hrvSDNN = hrvSDNN
        self.stepCount = stepCount
        self.mindfulMinutes = mindfulMinutes
    }
}
