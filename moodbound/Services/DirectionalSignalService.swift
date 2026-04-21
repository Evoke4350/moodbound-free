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

        // Per-series optional sources. A nil at index i means "no signal that
        // day"; we drop pairs where either side is nil rather than imputing a
        // sentinel like 0.5, which would otherwise pull every correlation
        // toward zero and falsely flag uninformative days as "neutral evidence".
        // sleepHours == 0 is the app's "unknown" convention, so it is also nil here.
        let sleepDeficit: [Double?] = sorted.map { $0.sleepHours > 0 ? max(0, 7.0 - $0.sleepHours) : nil }
        let nextDayMood: [Double?] = sorted.map { Double($0.moodLevel) }
        let triggerLoad: [Double?] = sorted.map { $0.triggerLoad7d }
        let nextDayAnxiety: [Double?] = sorted.map { Double($0.anxiety) }
        let medAdherence: [Double?] = sorted.map { $0.medAdherenceRate7d }
        let nextDayVolatility: [Double?] = sorted.map { $0.volatility7d }

        let sleepProbe = laggedCorrelation(source: sleepDeficit, target: nextDayMood, lag: lagDays)
        let triggerProbe = laggedCorrelation(source: triggerLoad, target: nextDayAnxiety, lag: lagDays)
        let medProbe = laggedCorrelation(source: medAdherence, target: nextDayVolatility, lag: lagDays)

        let candidates: [(String, String, LaggedCorrelation)] = [
            ("Sleep Deficit", "Next-Day Mood Elevation", sleepProbe),
            ("Trigger Load", "Next-Day Anxiety", triggerProbe),
            ("Medication Adherence", "Next-Day Volatility (inverse)", medProbe.negated),
        ]

        return candidates
            .filter { $0.2.pairs >= 6 && abs($0.2.r) >= 0.25 }
            .map { source, target, result in
                let confidence = min(0.95, abs(result.r) * sqrt(Double(result.pairs) / 20.0))
                return DirectionalSignalProbe(
                    source: source,
                    target: target,
                    lagDays: lagDays,
                    strength: result.r,
                    confidence: confidence,
                    caveat: standardCaveat
                )
            }
            .sorted { abs($0.strength) > abs($1.strength) }
    }

    private struct LaggedCorrelation {
        let r: Double
        let pairs: Int

        var negated: LaggedCorrelation { LaggedCorrelation(r: -r, pairs: pairs) }
        static let zero = LaggedCorrelation(r: 0, pairs: 0)
    }

    private static func laggedCorrelation(source: [Double?], target: [Double?], lag: Int) -> LaggedCorrelation {
        guard lag > 0 else { return .zero }
        guard source.count == target.count, source.count > lag else { return .zero }

        var x: [Double] = []
        var y: [Double] = []
        for index in 0..<(source.count - lag) {
            guard let sx = source[index], let ty = target[index + lag] else { continue }
            x.append(sx)
            y.append(ty)
        }

        return LaggedCorrelation(r: pearsonCorrelation(x: x, y: y), pairs: x.count)
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
