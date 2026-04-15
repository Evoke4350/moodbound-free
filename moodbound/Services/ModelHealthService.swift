import Foundation

enum ModelHealthLevel: String, Equatable {
    case healthy
    case watch
    case degraded
}

struct ModelHealthStatus: Equatable {
    let level: ModelHealthLevel
    let driftScore: Double
    let calibrationError: Double
    let staleDays: Int
    let alerts: [String]
}

enum ModelHealthService {
    static func assess(vectors: [TemporalFeatureVector], forecast: ProbabilisticScore, now: Date) -> ModelHealthStatus {
        let sorted = vectors.sorted { $0.timestamp < $1.timestamp }
        guard let latest = sorted.last else {
            return ModelHealthStatus(
                level: .watch,
                driftScore: 1,
                calibrationError: forecast.calibrationError,
                staleDays: 999,
                alerts: ["No feature vectors available for model health."]
            )
        }

        let drift = driftScore(vectors: sorted)
        let staleDays = max(0, Calendar.current.dateComponents([.day], from: latest.timestamp, to: now).day ?? 0)
        var alerts: [String] = []

        if drift >= 0.45 {
            alerts.append("Distribution drift is elevated.")
        }
        if forecast.calibrationError >= 0.2 {
            alerts.append("Forecast calibration error is above target.")
        }
        if staleDays >= 7 {
            alerts.append("Model inputs are stale. Log a new check-in.")
        }

        let level: ModelHealthLevel
        if drift >= 0.55 || forecast.calibrationError >= 0.3 || staleDays >= 14 {
            level = .degraded
        } else if drift >= 0.35 || forecast.calibrationError >= 0.18 || staleDays >= 7 {
            level = .watch
        } else {
            level = .healthy
        }

        return ModelHealthStatus(
            level: level,
            driftScore: drift,
            calibrationError: forecast.calibrationError,
            staleDays: staleDays,
            alerts: alerts
        )
    }

    private static func driftScore(vectors: [TemporalFeatureVector]) -> Double {
        let recent = Array(vectors.suffix(14))
        let baseline = Array(vectors.dropLast(min(14, vectors.count)).suffix(14))
        guard !recent.isEmpty, !baseline.isEmpty else { return 0.25 }

        let recentMood = mean(recent.map(\.moodLevel))
        let baseMood = mean(baseline.map(\.moodLevel))
        let recentSleep = mean(recent.map(\.sleepHours))
        let baseSleep = mean(baseline.map(\.sleepHours))
        let recentEnergy = mean(recent.map(\.energy))
        let baseEnergy = mean(baseline.map(\.energy))

        let moodShift = min(1, abs(recentMood - baseMood) / 3.0)
        let sleepShift = min(1, abs(recentSleep - baseSleep) / 4.0)
        let energyShift = min(1, abs(recentEnergy - baseEnergy) / 2.0)
        return (0.4 * moodShift) + (0.3 * sleepShift) + (0.3 * energyShift)
    }

    private static func mean(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / Double(values.count)
    }
}
