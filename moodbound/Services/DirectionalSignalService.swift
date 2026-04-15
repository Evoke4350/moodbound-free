import Foundation

struct DirectionalSignalProbe: Equatable {
    let source: String
    let target: String
    let lagDays: Int
    let strength: Double
    let confidence: Double
    let caveat: String
}

enum DirectionalSignalService {
    static let standardCaveat = "Directional statistical hint only. This is not diagnostic or causal proof."

    static func probes(vectors: [TemporalFeatureVector], lagDays: Int = 1) -> [DirectionalSignalProbe] {
        let sorted = vectors.sorted { $0.timestamp < $1.timestamp }
        guard sorted.count >= 8 else { return [] }

        let sleepDeficit = sorted.map { max(0, 7.0 - $0.sleepHours) }
        let nextDayMood = sorted.map(\.moodLevel)
        let triggerLoad = sorted.map { $0.triggerLoad7d ?? 0 }
        let nextDayAnxiety = sorted.map(\.anxiety)
        let medAdherence = sorted.map { $0.medAdherenceRate7d ?? 0.5 }
        let nextDayVolatility = sorted.map { $0.volatility7d ?? 0.5 }

        let candidates: [(String, String, Double)] = [
            ("Sleep Deficit", "Next-Day Mood Elevation", laggedCorrelation(source: sleepDeficit, target: nextDayMood, lag: lagDays)),
            ("Trigger Load", "Next-Day Anxiety", laggedCorrelation(source: triggerLoad, target: nextDayAnxiety, lag: lagDays)),
            ("Medication Adherence", "Next-Day Volatility (inverse)", -laggedCorrelation(source: medAdherence, target: nextDayVolatility, lag: lagDays)),
        ]

        return candidates
            .filter { abs($0.2) >= 0.25 }
            .map { source, target, corr in
                let confidence = min(0.95, abs(corr) * sqrt(Double(sorted.count) / 20.0))
                return DirectionalSignalProbe(
                    source: source,
                    target: target,
                    lagDays: lagDays,
                    strength: corr,
                    confidence: confidence,
                    caveat: standardCaveat
                )
            }
            .sorted { abs($0.strength) > abs($1.strength) }
    }

    private static func laggedCorrelation(source: [Double], target: [Double], lag: Int) -> Double {
        guard lag > 0 else { return 0 }
        guard source.count == target.count, source.count > lag else { return 0 }

        var x: [Double] = []
        var y: [Double] = []
        for index in 0..<(source.count - lag) {
            x.append(source[index])
            y.append(target[index + lag])
        }

        return pearsonCorrelation(x: x, y: y)
    }

    private static func pearsonCorrelation(x: [Double], y: [Double]) -> Double {
        guard x.count == y.count, x.count >= 3 else { return 0 }

        let meanX = x.reduce(0, +) / Double(x.count)
        let meanY = y.reduce(0, +) / Double(y.count)

        var numerator = 0.0
        var denomX = 0.0
        var denomY = 0.0

        for index in x.indices {
            let dx = x[index] - meanX
            let dy = y[index] - meanY
            numerator += dx * dy
            denomX += dx * dx
            denomY += dy * dy
        }

        guard denomX > 0, denomY > 0 else { return 0 }
        return numerator / sqrt(denomX * denomY)
    }
}
