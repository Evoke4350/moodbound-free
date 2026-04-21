import Foundation

enum ConformalCalibrationService {
    static func conformalize(raw: ProbabilisticScore, vectors: [TemporalFeatureVector]) -> ProbabilisticScore {
        let sorted = vectors.sorted { $0.timestamp < $1.timestamp }
        guard sorted.count >= 12 else { return raw }

        let scores = nonconformityScores(vectors: sorted)
        guard !scores.isEmpty else { return raw }

        let quantile = empiricalQuantile(scores, q: 0.9)
        let low = clamp(raw.value - quantile)
        let high = clamp(raw.value + quantile)

        return ProbabilisticScore(
            value: raw.value,
            ciLow: min(low, high),
            ciHigh: max(low, high),
            calibrationError: min(0.5, max(0, raw.calibrationError * 0.7)),
            rawValue: raw.rawValue
        )
    }

    private static func nonconformityScores(vectors: [TemporalFeatureVector]) -> [Double] {
        var scores: [Double] = []
        for index in 1..<vectors.count {
            let predicted = proxyRisk(vectors[index - 1])
            let realized = proxyOutcome(vectors[index])
            scores.append(abs(predicted - realized))
        }
        return scores
    }

    private static func proxyRisk(_ vector: TemporalFeatureVector) -> Double {
        let mood = abs(vector.moodLevel) / 3.0
        let sleep = max(0, (6.0 - vector.sleepHours) / 3.0)
        let volatility = min(1, (vector.volatility7d ?? 0.5) / 1.5)
        return clamp((0.45 * mood) + (0.35 * sleep) + (0.2 * volatility))
    }

    private static func proxyOutcome(_ vector: TemporalFeatureVector) -> Double {
        let manicOrDepressive = abs(vector.moodLevel) >= 2.0
        let severeSleep = vector.sleepHours <= 5.0 || vector.sleepHours >= 10.5
        let elevatedAnxiety = vector.anxiety >= 2.5
        return (manicOrDepressive || severeSleep || elevatedAnxiety) ? 1.0 : 0.0
    }

    private static func empiricalQuantile(_ values: [Double], q: Double) -> Double {
        let sorted = values.sorted()
        guard !sorted.isEmpty else { return 0 }
        let clamped = max(0, min(1, q))
        let index = Int((Double(sorted.count - 1) * clamped).rounded(.up))
        return sorted[min(sorted.count - 1, max(0, index))]
    }

    private static func clamp(_ value: Double, min: Double = 0, max: Double = 1) -> Double {
        Swift.max(min, Swift.min(max, value))
    }
}
