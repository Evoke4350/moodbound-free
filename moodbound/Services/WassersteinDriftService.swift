import Foundation

struct WassersteinDriftStatus: Equatable {
    let score: Double
    let threshold: Double
    let isDriftDetected: Bool
}

enum WassersteinDriftService {
    static func assess(vectors: [TemporalFeatureVector], threshold: Double = 0.22) -> WassersteinDriftStatus {
        let sorted = vectors.sorted { $0.timestamp < $1.timestamp }
        let recent = Array(sorted.suffix(21))
        let baseline = Array(sorted.dropLast(min(21, sorted.count)).suffix(21))

        guard recent.count >= 8, baseline.count >= 8 else {
            return WassersteinDriftStatus(score: 0, threshold: threshold, isDriftDetected: false)
        }

        let recentSignal = recent.map(signal)
        let baselineSignal = baseline.map(signal)
        let score = wasserstein1D(lhs: baselineSignal, rhs: recentSignal)

        return WassersteinDriftStatus(
            score: score,
            threshold: threshold,
            isDriftDetected: score >= threshold
        )
    }

    private static func signal(_ vector: TemporalFeatureVector) -> Double {
        let mood = abs(vector.moodLevel) / 3.0
        let sleep = max(0, (6.5 - vector.sleepHours) / 3.0)
        let energy = max(0, (vector.energy - 3.0) / 2.0)
        return (0.5 * mood) + (0.3 * sleep) + (0.2 * energy)
    }

    // Equal-weight empirical 1-Wasserstein distance in 1D.
    private static func wasserstein1D(lhs: [Double], rhs: [Double]) -> Double {
        let a = lhs.sorted()
        let b = rhs.sorted()
        let n = min(a.count, b.count)
        guard n > 0 else { return 0 }

        let total = (0..<n).reduce(0.0) { partial, index in
            partial + abs(a[index] - b[index])
        }
        return total / Double(n)
    }
}
