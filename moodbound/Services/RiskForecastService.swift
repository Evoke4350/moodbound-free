import Foundation

struct ProbabilisticScore: Equatable {
    let value: Double
    let ciLow: Double
    let ciHigh: Double
    let calibrationError: Double

    var ciWidth: Double {
        ciHigh - ciLow
    }
}

enum RiskForecastService {
    static let modelVersion = 1

    static func forecast7dRisk(vectors: [TemporalFeatureVector]) -> ProbabilisticScore {
        let sorted = vectors.sorted { $0.timestamp < $1.timestamp }
        guard !sorted.isEmpty else {
            return ProbabilisticScore(value: 0.5, ciLow: 0.0, ciHigh: 1.0, calibrationError: 1.0)
        }

        let latent = LatentStateService.inferStates(vectors: sorted)
        let changePoints = ChangePointService.detect(vectors: sorted)
        let recent = Array(sorted.suffix(14))

        let elevatedPosterior = average(latent.posteriors.suffix(14).map { $0.distribution.elevated })
        let depressivePosterior = average(latent.posteriors.suffix(14).map { $0.distribution.depressive })
        let lowSleepRate = fraction(recent.map { $0.sleepHours < 6.0 })
        let highVolatilityRate = fraction(recent.map { ($0.volatility7d ?? 0) >= 1.1 })
        let recentChangeRate = min(1.0, Double(changePoints.count) / max(1.0, Double(recent.count / 3)))

        let linearScore =
            (1.2 * elevatedPosterior) +
            (1.2 * depressivePosterior) +
            (0.9 * lowSleepRate) +
            (0.8 * highVolatilityRate) +
            (0.7 * recentChangeRate) -
            1.65

        let value = sigmoid(linearScore)
        let sampleSize = Double(recent.count)
        let uncertaintyScale = max(0.08, 0.35 / sqrt(max(1.0, sampleSize)))
        let low = clamp(value - uncertaintyScale)
        let high = clamp(value + uncertaintyScale)

        // Heuristic expected calibration error proxy (shrinks with data volume).
        let calibrationError = min(0.5, 0.22 / sqrt(max(1.0, sampleSize)))

        return ProbabilisticScore(
            value: value,
            ciLow: min(low, high),
            ciHigh: max(low, high),
            calibrationError: calibrationError
        )
    }

    private static func sigmoid(_ x: Double) -> Double {
        1.0 / (1.0 + exp(-x))
    }

    private static func clamp(_ value: Double, min: Double = 0.0, max: Double = 1.0) -> Double {
        Swift.max(min, Swift.min(max, value))
    }

    private static func average(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / Double(values.count)
    }

    private static func fraction(_ bools: [Bool]) -> Double {
        guard !bools.isEmpty else { return 0 }
        return Double(bools.filter { $0 }.count) / Double(bools.count)
    }
}
