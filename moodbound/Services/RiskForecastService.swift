import Foundation

struct ProbabilisticScore: Equatable {
    let value: Double
    let ciLow: Double
    let ciHigh: Double
    let calibrationError: Double
    // Pre-shrinkage forecast value. Downstream consumers (BayesianSafetyEngine)
    // need the unattenuated signal to drive their own posterior — feeding the
    // already-shrunk `value` would compound shrinkage and silently suppress
    // genuine distress signals at intermediate sample sizes (N=4..10). UI
    // surfaces should use `value` (shrunk); model math should use `rawValue`.
    let rawValue: Double

    var ciWidth: Double {
        ciHigh - ciLow
    }

    // `rawValue` defaults to `value` for ergonomic test fixture construction,
    // but any production path that constructs a ProbabilisticScore from a
    // shrunk number MUST pass the unshrunk value explicitly. Without that,
    // BayesianSafetyEngine will silently re-introduce the double-shrinkage
    // bug — its LR reads `rawValue` precisely to avoid that compound.
    init(value: Double, ciLow: Double, ciHigh: Double, calibrationError: Double, rawValue: Double? = nil) {
        self.value = value
        self.ciLow = ciLow
        self.ciHigh = ciHigh
        self.calibrationError = calibrationError
        self.rawValue = rawValue ?? value
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
        // sleepHours == 0 is the app's "unknown" sentinel; drop those days
        // from the rate so skipped entries don't inflate "low sleep" signal.
        let lowSleepRate = fraction(recent.compactMap { v -> Bool? in
            guard v.sleepHours > 0 else { return nil }
            return v.sleepHours < 6.0
        })
        let highVolatilityRate = fraction(recent.map { ($0.volatility7d ?? 0) >= 1.1 })
        let changeRate = recentChangeRate(changeCount: changePoints.count, recentCount: recent.count)

        let linearScore =
            (1.2 * elevatedPosterior) +
            (1.2 * depressivePosterior) +
            (0.9 * lowSleepRate) +
            (0.8 * highVolatilityRate) +
            (0.7 * changeRate) -
            1.65

        // Pull the raw sigmoid output toward the neutral prior (0.5) when
        // the recent window is sparse. We use sqrt(N/14) — the same scaling
        // family as the CI uncertainty term below — so confidence builds
        // faster than linear in the 4–10 regime that the user actually sees
        // most often, while still pinning the headline near 0.5 at N=1..2.
        // The raw value is preserved on the result so downstream consumers
        // (BayesianSafetyEngine) can compute their own posterior without
        // double-shrinking through this attenuated value.
        let rawValue = sigmoid(linearScore)
        let sampleSize = Double(recent.count)
        let shrinkWeight = min(1.0, sqrt(sampleSize / 14.0))
        let value = (shrinkWeight * rawValue) + ((1.0 - shrinkWeight) * 0.5)
        let uncertaintyScale = max(0.08, 0.35 / sqrt(max(1.0, sampleSize)))
        let low = clamp(value - uncertaintyScale)
        let high = clamp(value + uncertaintyScale)

        // Heuristic expected calibration error proxy (shrinks with data volume).
        let calibrationError = min(0.5, 0.22 / sqrt(max(1.0, sampleSize)))

        return ProbabilisticScore(
            value: value,
            ciLow: min(low, high),
            ciHigh: max(low, high),
            calibrationError: calibrationError,
            rawValue: rawValue
        )
    }

    // Internal so tests can pin the small-N behavior. Previously this was
    // `recent.count / 3` (integer division), which made N=1,2 collapse to 0
    // and N=4,5 collapse to 1 — flattening the rate scale at the low end so
    // a single change point would saturate to 1.0 across N=1..5. Double
    // division keeps the denominator continuous; max(1.0, …) prevents
    // amplification when N<3 would otherwise inflate the rate above 1.
    static func recentChangeRate(changeCount: Int, recentCount: Int) -> Double {
        min(1.0, Double(changeCount) / max(1.0, Double(recentCount) / 3.0))
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
