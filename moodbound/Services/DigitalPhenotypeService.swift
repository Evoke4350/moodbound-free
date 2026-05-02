import Foundation

struct DigitalPhenotypeCard: Equatable, Identifiable {
    let id: String
    let title: String
    let metricValue: Double
    let uncertainty: Double
    let interpretationBand: String
    let isSufficientData: Bool
}

enum DigitalPhenotypeService {
    static func cards(vectors: [TemporalFeatureVector]) -> [DigitalPhenotypeCard] {
        let sorted = vectors.sorted { $0.timestamp < $1.timestamp }
        guard sorted.count >= 5 else {
            return [
                insufficient(id: "sleep-regularity", title: "Sleep Regularity"),
                insufficient(id: "activation-slope", title: "Activation Slope"),
                insufficient(id: "recovery-half-life", title: "Recovery Half-Life"),
            ]
        }

        let sleepCard = sleepRegularityCard(vectors: sorted)
        let activationCard = activationSlopeCard(vectors: sorted)
        let recoveryCard = recoveryHalfLifeCard(vectors: sorted)
        return [sleepCard, activationCard, recoveryCard]
    }

    private static func sleepRegularityCard(vectors: [TemporalFeatureVector]) -> DigitalPhenotypeCard {
        // sleepHours == 0 is the project-wide "unknown" sentinel. FeatureStore
        // emits it for every non-first-of-day vector, and entries with no
        // recorded sleep also store 0. Treat both as missing rather than as
        // genuine 0-hour nights, which would crater the regularity score.
        let values = vectors.suffix(21).map(\.sleepHours).filter { $0 > 0 }
        let std = standardDeviation(values)
        let regularity = max(0, min(100, 100 - (std * 20)))
        let band: String
        if regularity >= 75 {
            band = "Stable"
        } else if regularity >= 45 {
            band = "Variable"
        } else {
            band = "Disrupted"
        }
        return DigitalPhenotypeCard(
            id: "sleep-regularity",
            title: "Sleep Regularity",
            metricValue: regularity,
            uncertainty: uncertainty(sampleSize: values.count),
            interpretationBand: band,
            isSufficientData: values.count >= 7
        )
    }

    private static func activationSlopeCard(vectors: [TemporalFeatureVector]) -> DigitalPhenotypeCard {
        let values = Array(vectors.suffix(14))
        let slope = linearSlope(values.map { ($0.timestamp.timeIntervalSince1970 / 86_400.0, (($0.energy - 3.0) / 2.0) + ($0.moodLevel / 3.0)) })
        let band: String
        if slope >= 0.06 {
            band = "Rising"
        } else if slope <= -0.06 {
            band = "Falling"
        } else {
            band = "Steady"
        }
        return DigitalPhenotypeCard(
            id: "activation-slope",
            title: "Activation Slope",
            metricValue: slope,
            uncertainty: uncertainty(sampleSize: values.count),
            interpretationBand: band,
            isSufficientData: values.count >= 7
        )
    }

    private static func recoveryHalfLifeCard(vectors: [TemporalFeatureVector]) -> DigitalPhenotypeCard {
        let values = Array(vectors.suffix(30))
        // Skip the sleep contribution when sleep is unknown (0); otherwise
        // every same-day duplicate vector or sleep-less entry would inflate
        // the severity score with a phantom "you slept 0h" signal.
        let severities = values.map { vector -> Double in
            let sleepDeficit = vector.sleepHours > 0 ? (max(0, 6.5 - vector.sleepHours) / 2.0) : 0
            return abs(vector.moodLevel) + sleepDeficit
        }
        guard let peak = severities.enumerated().max(by: { $0.element < $1.element }), peak.element >= 0.8 else {
            return insufficient(id: "recovery-half-life", title: "Recovery Half-Life")
        }

        let target = peak.element / 2.0
        var daysToRecover: Double = 0
        var recovered = false
        for index in peak.offset..<severities.count {
            if severities[index] <= target {
                let start = values[peak.offset].timestamp
                let end = values[index].timestamp
                daysToRecover = max(0, end.timeIntervalSince(start) / 86_400.0)
                recovered = true
                break
            }
        }

        guard recovered else {
            return DigitalPhenotypeCard(
                id: "recovery-half-life",
                title: "Recovery Half-Life",
                metricValue: 0,
                uncertainty: 0.9,
                interpretationBand: "Pending",
                isSufficientData: false
            )
        }

        let band: String
        if daysToRecover <= 2 {
            band = "Fast"
        } else if daysToRecover <= 5 {
            band = "Moderate"
        } else {
            band = "Slow"
        }

        return DigitalPhenotypeCard(
            id: "recovery-half-life",
            title: "Recovery Half-Life",
            metricValue: daysToRecover,
            uncertainty: uncertainty(sampleSize: values.count),
            interpretationBand: band,
            isSufficientData: true
        )
    }

    private static func insufficient(id: String, title: String) -> DigitalPhenotypeCard {
        DigitalPhenotypeCard(
            id: id,
            title: title,
            metricValue: 0,
            uncertainty: 1,
            interpretationBand: "Insufficient Data",
            isSufficientData: false
        )
    }

    private static func uncertainty(sampleSize: Int) -> Double {
        max(0.05, min(1.0, 1.0 / sqrt(Double(max(1, sampleSize)))))
    }

    private static func standardDeviation(_ values: [Double]) -> Double {
        guard values.count > 1 else { return 0 }
        let mean = values.reduce(0, +) / Double(values.count)
        let variance = values.reduce(0) { partial, value in
            let delta = value - mean
            return partial + (delta * delta)
        } / Double(values.count - 1)
        return sqrt(variance)
    }

    private static func linearSlope(_ samples: [(x: Double, y: Double)]) -> Double {
        guard samples.count > 1 else { return 0 }
        let meanX = samples.map(\.x).reduce(0, +) / Double(samples.count)
        let meanY = samples.map(\.y).reduce(0, +) / Double(samples.count)
        var numerator = 0.0
        var denominator = 0.0
        for sample in samples {
            let dx = sample.x - meanX
            numerator += dx * (sample.y - meanY)
            denominator += dx * dx
        }
        guard denominator > 0 else { return 0 }
        return numerator / denominator
    }
}
