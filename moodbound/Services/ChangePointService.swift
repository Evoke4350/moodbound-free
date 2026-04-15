import Foundation

enum ChangeDirection {
    case upward
    case downward
}

struct ChangePointEvent: Equatable {
    let timestamp: Date
    let score: Double
    let direction: ChangeDirection
}

enum ChangePointService {
    static let modelVersion = 1

    static func detect(
        vectors: [TemporalFeatureVector],
        threshold: Double = 1.8,
        drift: Double = 0.12
    ) -> [ChangePointEvent] {
        let sorted = vectors.sorted { $0.timestamp < $1.timestamp }
        guard sorted.count >= 3 else { return [] }

        let signal = sorted.map(compositeSignal(_:))

        var positiveCusum = 0.0
        var negativeCusum = 0.0
        var events: [ChangePointEvent] = []

        for index in 1..<signal.count {
            let delta = signal[index] - signal[index - 1]

            positiveCusum = max(0, positiveCusum + delta - drift)
            negativeCusum = min(0, negativeCusum + delta + drift)

            if positiveCusum >= threshold {
                events.append(
                    ChangePointEvent(
                        timestamp: sorted[index].timestamp,
                        score: positiveCusum,
                        direction: .upward
                    )
                )
                positiveCusum = 0
            }

            if abs(negativeCusum) >= threshold {
                events.append(
                    ChangePointEvent(
                        timestamp: sorted[index].timestamp,
                        score: abs(negativeCusum),
                        direction: .downward
                    )
                )
                negativeCusum = 0
            }
        }

        return events
    }

    private static func compositeSignal(_ vector: TemporalFeatureVector) -> Double {
        let moodComponent = vector.moodLevel
        let energyComponent = (vector.energy - 3.0) * 0.45
        let sleepComponent = (7.0 - vector.sleepHours) * 0.30
        return moodComponent + energyComponent + sleepComponent
    }
}
