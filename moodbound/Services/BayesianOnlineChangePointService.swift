import Foundation

struct RunLengthPosteriorPoint: Equatable {
    let timestamp: Date
    let mostLikelyRunLength: Int
    let changeProbability: Double
}

struct BOCPDResult: Equatable {
    let latestChangeProbability: Double
    let points: [RunLengthPosteriorPoint]
}

enum BayesianOnlineChangePointService {
    static func detect(vectors: [TemporalFeatureVector], hazard: Double = 1.0 / 28.0, maxRunLength: Int = 90) -> BOCPDResult {
        let sorted = vectors.sorted { $0.timestamp < $1.timestamp }
        guard sorted.count >= 4 else {
            return BOCPDResult(latestChangeProbability: 0, points: [])
        }

        let observations = sorted.map(observation)
        var runLogProb: [Double] = [0.0] // run length 0 has all mass at t=0
        var points: [RunLengthPosteriorPoint] = []

        for index in observations.indices {
            let limit = min(maxRunLength, runLogProb.count)
            var growthLogProb = Array(repeating: -Double.infinity, count: limit + 1)
            var cpAccumulator: [Double] = []

            for runLength in 0..<limit {
                let predictive = predictiveLogProb(observations: observations, index: index, runLength: runLength)
                let previous = runLogProb[runLength]
                let grow = previous + log1p(-hazard) + predictive
                growthLogProb[runLength + 1] = logAddExp(growthLogProb[runLength + 1], grow)
                cpAccumulator.append(previous + log(hazard) + predictive)
            }

            let cpLogProb = logSumExp(cpAccumulator)
            growthLogProb[0] = cpLogProb

            let normalizer = logSumExp(growthLogProb)
            runLogProb = growthLogProb.map { $0 - normalizer }

            let baseChangeProbability = exp(runLogProb[0])
            let surpriseBoost = localSurprise(observations: observations, index: index)
            let changeProbability = clamp(baseChangeProbability + (0.7 * surpriseBoost * (1.0 - baseChangeProbability)))
            let mostLikely = runLogProb.enumerated().max(by: { $0.element < $1.element })?.offset ?? 0
            points.append(
                RunLengthPosteriorPoint(
                    timestamp: sorted[index].timestamp,
                    mostLikelyRunLength: mostLikely,
                    changeProbability: changeProbability
                )
            )
        }

        // Use a recency-weighted change score so abrupt shifts remain visible for a short period
        // instead of collapsing immediately to the baseline hazard after adaptation.
        let weighted = points.enumerated().map { index, point in
            let age = Double((points.count - 1) - index)
            let decay = exp(-age / 14.0)
            return point.changeProbability * decay
        }

        return BOCPDResult(
            latestChangeProbability: weighted.max() ?? 0,
            points: points
        )
    }

    private static func observation(_ vector: TemporalFeatureVector) -> Double {
        let mood = abs(vector.moodLevel) / 3.0
        let sleepPenalty = max(0, (6.5 - vector.sleepHours) / 3.0)
        let energy = max(0, (vector.energy - 3.0) / 2.0)
        return (0.5 * mood) + (0.3 * sleepPenalty) + (0.2 * energy)
    }

    // Student-t predictive approximation with weak-Normal prior and unknown variance.
    private static func predictiveLogProb(observations: [Double], index: Int, runLength: Int) -> Double {
        if runLength == 0 {
            return normalLogPDF(x: observations[index], mean: 0.4, variance: 0.3)
        }

        let start = max(0, index - runLength)
        let window = observations[start..<index]
        let mean = window.reduce(0, +) / Double(window.count)
        let variance = max(1e-4, sampleVariance(Array(window), mean: mean))
        // one-step predictive variance inflation
        return normalLogPDF(x: observations[index], mean: mean, variance: variance * (1.0 + 1.0 / Double(window.count)))
    }

    private static func sampleVariance(_ values: [Double], mean: Double) -> Double {
        guard values.count > 1 else { return 0.05 }
        let sum = values.reduce(0.0) { partial, value in
            let delta = value - mean
            return partial + (delta * delta)
        }
        return sum / Double(values.count - 1)
    }

    private static func normalLogPDF(x: Double, mean: Double, variance: Double) -> Double {
        -0.5 * (log(2.0 * .pi * variance) + ((x - mean) * (x - mean) / variance))
    }

    private static func localSurprise(observations: [Double], index: Int, lookback: Int = 7) -> Double {
        guard index >= 3 else { return 0 }
        let start = max(0, index - lookback)
        let window = Array(observations[start..<index])
        guard window.count >= 3 else { return 0 }
        let mean = window.reduce(0, +) / Double(window.count)
        let variance = max(1e-4, sampleVariance(window, mean: mean))
        let z = abs(observations[index] - mean) / sqrt(variance)
        // Logistic mapping: ~0 under low surprise, rises quickly once z exceeds ~2 SD.
        return 1.0 / (1.0 + exp(-(z - 2.0)))
    }

    private static func logSumExp(_ values: [Double]) -> Double {
        guard let maxValue = values.max(), maxValue.isFinite else { return -Double.infinity }
        let sum = values.reduce(0.0) { partial, value in
            partial + exp(value - maxValue)
        }
        return maxValue + log(sum)
    }

    private static func logAddExp(_ a: Double, _ b: Double) -> Double {
        if !a.isFinite { return b }
        if !b.isFinite { return a }
        let maxValue = max(a, b)
        return maxValue + log(exp(a - maxValue) + exp(b - maxValue))
    }

    private static func clamp(_ value: Double, min: Double = 0, max: Double = 1) -> Double {
        Swift.max(min, Swift.min(max, value))
    }
}
