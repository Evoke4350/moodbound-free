import Foundation
import SwiftData

struct TemporalFeatureVector: Equatable {
    let timestamp: Date
    let moodLevel: Double
    let sleepHours: Double
    let energy: Double
    let anxiety: Double
    let irritability: Double
    let medAdherenceRate7d: Double?
    let triggerLoad7d: Double?
    let volatility7d: Double?
    let circadianDrift7d: Double?
    var restingHeartRate: Double? = nil
    var hrvSDNN: Double? = nil
    var stepCount: Double? = nil
    var mindfulMinutes: Double? = nil
}

struct FeatureStoreSnapshot {
    let featureSchemaVersion: Int
    let generatedAt: Date
    let vectors: [TemporalFeatureVector]
}

enum FeatureStoreService {
    static let featureSchemaVersion = 1

    static func materialize(
        entries: [MoodEntry],
        now: Date = AppClock.now,
        calendar: Calendar = .current
    ) -> FeatureStoreSnapshot {
        let vectors = buildVectors(entries: entries, calendar: calendar)
        return FeatureStoreSnapshot(
            featureSchemaVersion: featureSchemaVersion,
            generatedAt: now,
            vectors: vectors
        )
    }

    static func buildVectors(
        entries: [MoodEntry],
        calendar: Calendar = .current
    ) -> [TemporalFeatureVector] {
        let sorted = entries.sorted { $0.timestamp < $1.timestamp }
        // Sleep is a once-per-night measurement that the entry form already
        // inherits across same-day entries. Duplicating it into every vector
        // makes downstream regularity / recovery scores look more stable
        // than they are. Keep the sleep value on the *first* entry of each
        // calendar day; subsequent same-day vectors get 0 (the project-wide
        // "unknown" sentinel) so sleep-aware services treat them as missing.
        var earliestEntryIDByDay: [Date: PersistentIdentifier] = [:]
        for entry in sorted {
            let day = calendar.startOfDay(for: entry.timestamp)
            if earliestEntryIDByDay[day] == nil {
                earliestEntryIDByDay[day] = entry.persistentModelID
            }
        }

        return sorted.map { entry in
            let window7d = window(
                entries: sorted,
                endingAt: entry.timestamp,
                daysBack: 7,
                calendar: calendar
            )
            let preceding7d = precedingWindow(
                entries: sorted,
                before: entry.timestamp,
                daysBack: 7,
                calendar: calendar
            )

            let day = calendar.startOfDay(for: entry.timestamp)
            let isFirstOfDay = earliestEntryIDByDay[day] == entry.persistentModelID
            let sleepValue = isFirstOfDay ? entry.sleepHours : 0

            return TemporalFeatureVector(
                timestamp: entry.timestamp,
                moodLevel: Double(entry.moodLevel),
                sleepHours: sleepValue,
                energy: Double(entry.energy),
                anxiety: Double(entry.anxiety),
                irritability: Double(entry.irritability),
                medAdherenceRate7d: medAdherenceRate(entries: window7d),
                triggerLoad7d: triggerLoad(entries: window7d),
                volatility7d: moodVolatility(entries: window7d),
                circadianDrift7d: circadianDrift(
                    current: entry,
                    previousEntries: preceding7d,
                    calendar: calendar
                ),
                restingHeartRate: entry.restingHeartRate,
                hrvSDNN: entry.hrvSDNN,
                stepCount: entry.stepCount.map { Double($0) },
                mindfulMinutes: entry.mindfulMinutes
            )
        }
    }

    private static func window(
        entries: [MoodEntry],
        endingAt endDate: Date,
        daysBack: Int,
        calendar: Calendar
    ) -> [MoodEntry] {
        let start = calendar.date(byAdding: .day, value: -daysBack, to: endDate) ?? endDate
        return entries.filter { $0.timestamp >= start && $0.timestamp <= endDate }
    }

    private static func precedingWindow(
        entries: [MoodEntry],
        before endDate: Date,
        daysBack: Int,
        calendar: Calendar
    ) -> [MoodEntry] {
        let start = calendar.date(byAdding: .day, value: -daysBack, to: endDate) ?? endDate
        return entries.filter { $0.timestamp >= start && $0.timestamp < endDate }
    }

    private static func medAdherenceRate(entries: [MoodEntry]) -> Double? {
        let events = entries.flatMap(\.medicationAdherenceEvents)
        guard !events.isEmpty else { return nil }
        let takenCount = events.filter(\.taken).count
        return Double(takenCount) / Double(events.count)
    }

    private static func triggerLoad(entries: [MoodEntry]) -> Double? {
        let intensities = entries
            .flatMap(\.triggerEvents)
            .map(\.intensity)
        guard !intensities.isEmpty else { return nil }
        return Double(intensities.reduce(0, +)) / Double(intensities.count)
    }

    private static func moodVolatility(entries: [MoodEntry]) -> Double? {
        let moods = entries.map { Double($0.moodLevel) }
        guard moods.count >= 2 else { return nil }
        let mean = moods.reduce(0, +) / Double(moods.count)
        let variance = moods.reduce(0) { partial, value in
            let diff = value - mean
            return partial + (diff * diff)
        } / Double(moods.count)
        return sqrt(variance)
    }

    private static func circadianDrift(
        current: MoodEntry,
        previousEntries: [MoodEntry],
        calendar: Calendar
    ) -> Double? {
        guard !previousEntries.isEmpty else { return nil }

        let baselineHours = previousEntries.map { hourFraction(for: $0.timestamp, calendar: calendar) }
        let baseline = baselineHours.reduce(0, +) / Double(baselineHours.count)
        let currentHour = hourFraction(for: current.timestamp, calendar: calendar)
        return wrappedHourDistance(from: currentHour, to: baseline)
    }

    private static func hourFraction(for date: Date, calendar: Calendar) -> Double {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        let hour = Double(components.hour ?? 0)
        let minute = Double(components.minute ?? 0)
        return hour + (minute / 60.0)
    }

    private static func wrappedHourDistance(from lhs: Double, to rhs: Double) -> Double {
        let raw = abs(lhs - rhs)
        return min(raw, 24.0 - raw)
    }
}
