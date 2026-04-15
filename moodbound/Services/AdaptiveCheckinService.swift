import Foundation

struct AdaptivePrompt: Equatable, Identifiable {
    let id: String
    let title: String
    let prompt: String
    let rationale: String
    let informationGain: Double
}

enum AdaptiveCheckinService {
    static func nextPrompts(
        entries: [MoodEntry],
        vectors: [TemporalFeatureVector],
        forecast: ProbabilisticScore,
        attributions: [TriggerAttribution],
        maxPrompts: Int = 3
    ) -> [AdaptivePrompt] {
        let sortedEntries = entries.sorted { $0.timestamp < $1.timestamp }
        let missingMedicationRate = medicationUnknownRate(entries: sortedEntries)
        let sleepIrregularity = sleepStdDev(entries: sortedEntries)
        let triggerUncertainty = attributions.first.map { 1.0 - $0.confidence } ?? 1.0
        let forecastUncertainty = max(0, forecast.ciWidth + forecast.calibrationError)
        let volatilityGap = max(0, 1.0 - confidenceFromVolatility(vectors))
        let expectedResolution = 0.55

        let candidates: [AdaptivePrompt] = [
            AdaptivePrompt(
                id: "sleep-routine",
                title: "Sleep Detail",
                prompt: "How consistent were your bedtime and wake time since the last check-in?",
                rationale: "Sleep timing variability is a major uncertainty driver right now.",
                informationGain: infoGain(priorUncertainty: min(1.0, sleepIrregularity / 2.0), expectedResolution: expectedResolution)
            ),
            AdaptivePrompt(
                id: "medication-adherence",
                title: "Medication Check",
                prompt: "Did you take each scheduled medication today?",
                rationale: "Medication adherence signal coverage is incomplete.",
                informationGain: infoGain(priorUncertainty: missingMedicationRate, expectedResolution: expectedResolution)
            ),
            AdaptivePrompt(
                id: "trigger-context",
                title: "Trigger Context",
                prompt: "Were there any notable stressors or trigger events today?",
                rationale: "Trigger attribution confidence can improve with one more explicit tag.",
                informationGain: infoGain(priorUncertainty: triggerUncertainty, expectedResolution: expectedResolution)
            ),
            AdaptivePrompt(
                id: "activation-detail",
                title: "Activation Detail",
                prompt: "Did your energy feel unusually driven, restless, or slowed today?",
                rationale: "Activation trend uncertainty is currently elevated.",
                informationGain: infoGain(priorUncertainty: max(forecastUncertainty, volatilityGap), expectedResolution: expectedResolution)
            ),
        ]

        return candidates
            .filter { $0.informationGain >= 0.12 }
            .sorted { $0.informationGain > $1.informationGain }
            .prefix(maxPrompts)
            .map { $0 }
    }

    private static func medicationUnknownRate(entries: [MoodEntry]) -> Double {
        guard !entries.isEmpty else { return 1 }
        let unknown = entries.filter { $0.medicationAdherenceEvents.isEmpty }.count
        return Double(unknown) / Double(entries.count)
    }

    private static func sleepStdDev(entries: [MoodEntry]) -> Double {
        let values = entries.suffix(14).map(\.sleepHours)
        guard values.count > 1 else { return 0 }
        let mean = values.reduce(0, +) / Double(values.count)
        let variance = values.reduce(0) { sum, value in
            let delta = value - mean
            return sum + (delta * delta)
        } / Double(values.count - 1)
        return sqrt(variance)
    }

    private static func confidenceFromVolatility(_ vectors: [TemporalFeatureVector]) -> Double {
        let values = vectors.suffix(14).compactMap(\.volatility7d)
        guard !values.isEmpty else { return 0.2 }
        let mean = values.reduce(0, +) / Double(values.count)
        return max(0, min(1, 1.0 - (mean / 2.0)))
    }

    // Expected information gain from reducing an uncertainty budget by an expected resolution fraction.
    private static func infoGain(priorUncertainty: Double, expectedResolution: Double) -> Double {
        let prior = max(0, min(1, priorUncertainty))
        let resolution = max(0, min(1, expectedResolution))
        return prior * resolution
    }
}
