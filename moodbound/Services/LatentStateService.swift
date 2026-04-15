import Foundation

enum LatentMoodState: CaseIterable {
    case depressive
    case stable
    case elevated
    case unstable
}

struct LatentStateDistribution: Equatable {
    let depressive: Double
    let stable: Double
    let elevated: Double
    let unstable: Double

    var sum: Double {
        depressive + stable + elevated + unstable
    }

    var dominantState: LatentMoodState {
        let pairs: [(LatentMoodState, Double)] = [
            (.depressive, depressive),
            (.stable, stable),
            (.elevated, elevated),
            (.unstable, unstable),
        ]
        return pairs.max(by: { $0.1 < $1.1 })?.0 ?? .stable
    }

    subscript(_ state: LatentMoodState) -> Double {
        switch state {
        case .depressive: return depressive
        case .stable: return stable
        case .elevated: return elevated
        case .unstable: return unstable
        }
    }
}

struct LatentStateDayPosterior: Equatable {
    let timestamp: Date
    let distribution: LatentStateDistribution
}

struct LatentStateResult {
    let modelVersion: Int
    let posteriors: [LatentStateDayPosterior]
}

enum LatentStateService {
    static let modelVersion = 1

    static func inferStates(vectors: [TemporalFeatureVector]) -> LatentStateResult {
        let sorted = vectors.sorted { $0.timestamp < $1.timestamp }
        guard !sorted.isEmpty else {
            return LatentStateResult(modelVersion: modelVersion, posteriors: [])
        }

        let states = LatentMoodState.allCases
        let stateCount = states.count
        let transition = transitionMatrix()
        let emission = sorted.map { vector in
            states.map { state in emissionLikelihood(for: state, vector: vector) }
        }

        var forward = Array(
            repeating: Array(repeating: 0.0, count: stateCount),
            count: sorted.count
        )
        let initial = Array(repeating: 1.0 / Double(stateCount), count: stateCount)
        for j in 0..<stateCount {
            forward[0][j] = initial[j] * emission[0][j]
        }
        normalize(&forward[0])

        if sorted.count > 1 {
            for t in 1..<sorted.count {
                for j in 0..<stateCount {
                    var sum = 0.0
                    for i in 0..<stateCount {
                        sum += forward[t - 1][i] * transition[i][j]
                    }
                    forward[t][j] = sum * emission[t][j]
                }
                normalize(&forward[t])
            }
        }

        var backward = Array(
            repeating: Array(repeating: 0.0, count: stateCount),
            count: sorted.count
        )
        backward[sorted.count - 1] = Array(repeating: 1.0 / Double(stateCount), count: stateCount)
        if sorted.count > 1 {
            for t in stride(from: sorted.count - 2, through: 0, by: -1) {
                for i in 0..<stateCount {
                    var sum = 0.0
                    for j in 0..<stateCount {
                        sum += transition[i][j] * emission[t + 1][j] * backward[t + 1][j]
                    }
                    backward[t][i] = sum
                }
                normalize(&backward[t])
            }
        }

        var posteriors: [LatentStateDayPosterior] = []
        posteriors.reserveCapacity(sorted.count)

        for t in 0..<sorted.count {
            var gamma = Array(repeating: 0.0, count: stateCount)
            for i in 0..<stateCount {
                gamma[i] = forward[t][i] * backward[t][i]
            }
            normalize(&gamma)

            let distribution = LatentStateDistribution(
                depressive: gamma[0],
                stable: gamma[1],
                elevated: gamma[2],
                unstable: gamma[3]
            )
            posteriors.append(
                LatentStateDayPosterior(
                    timestamp: sorted[t].timestamp,
                    distribution: distribution
                )
            )
        }

        return LatentStateResult(modelVersion: modelVersion, posteriors: posteriors)
    }

    static func naiveState(for vector: TemporalFeatureVector) -> LatentMoodState {
        if (vector.volatility7d ?? 0) >= 1.25 {
            return .unstable
        }
        if vector.moodLevel <= -0.75 {
            return .depressive
        }
        if vector.moodLevel >= 0.75 {
            return .elevated
        }
        return .stable
    }

    private static func transitionMatrix() -> [[Double]] {
        [
            [0.86, 0.09, 0.01, 0.04], // depressive ->
            [0.07, 0.86, 0.04, 0.03], // stable ->
            [0.01, 0.10, 0.86, 0.03], // elevated ->
            [0.12, 0.20, 0.12, 0.56], // unstable ->
        ]
    }

    private static func emissionLikelihood(
        for state: LatentMoodState,
        vector: TemporalFeatureVector
    ) -> Double {
        let targetMood: Double
        let targetSleep: Double
        let targetEnergy: Double
        let targetVolatility: Double

        switch state {
        case .depressive:
            targetMood = -1.9
            targetSleep = 9.0
            targetEnergy = 2.0
            targetVolatility = 0.8
        case .stable:
            targetMood = 0.0
            targetSleep = 7.5
            targetEnergy = 3.0
            targetVolatility = 0.45
        case .elevated:
            targetMood = 1.9
            targetSleep = 5.5
            targetEnergy = 4.3
            targetVolatility = 0.9
        case .unstable:
            targetMood = 0.0
            targetSleep = 7.0
            targetEnergy = 3.2
            targetVolatility = 1.55
        }

        let moodScore = gaussian(x: vector.moodLevel, mean: targetMood, sigma: 1.05)
        let sleepScore = gaussian(x: vector.sleepHours, mean: targetSleep, sigma: 2.2)
        let energyScore = gaussian(x: vector.energy, mean: targetEnergy, sigma: 1.1)
        let volatilityScore = gaussian(
            x: vector.volatility7d ?? targetVolatility,
            mean: targetVolatility,
            sigma: 0.7
        )

        return max(1e-9, moodScore * sleepScore * energyScore * volatilityScore)
    }

    private static func gaussian(x: Double, mean: Double, sigma: Double) -> Double {
        guard sigma > 0 else { return 0 }
        let z = (x - mean) / sigma
        return exp(-0.5 * z * z)
    }

    private static func normalize(_ values: inout [Double]) {
        let total = values.reduce(0, +)
        guard total > 0 else {
            let uniform = 1.0 / Double(max(values.count, 1))
            for index in values.indices {
                values[index] = uniform
            }
            return
        }

        for index in values.indices {
            values[index] /= total
        }
    }
}
