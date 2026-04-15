import Foundation

struct TriggerSignalEvent: Equatable {
    let timestamp: Date
    let triggerName: String
    let intensity: Int
}

struct TriggerAttribution: Equatable {
    let triggerName: String
    let score: Double
    let confidence: Double
    let evidenceWindowStart: Date
    let evidenceWindowEnd: Date
    let supportingEvents: Int
}

enum TriggerAttributionService {
    static func rank(
        vectors: [TemporalFeatureVector],
        triggerEvents: [TriggerSignalEvent],
        topK: Int = 3
    ) -> [TriggerAttribution] {
        let sortedVectors = vectors.sorted { $0.timestamp < $1.timestamp }
        guard sortedVectors.count >= 5 else { return [] }

        let baselineRisk = average(sortedVectors.map(riskScore))
        var grouped: [String: [Double]] = [:]
        var groupedTimestamps: [String: [Date]] = [:]

        for event in triggerEvents {
            guard let vector = nearestVector(to: event.timestamp, vectors: sortedVectors) else { continue }
            let risk = riskScore(vector) * (1.0 + (Double(max(1, min(3, event.intensity))) - 1.0) * 0.15)
            grouped[event.triggerName, default: []].append(risk)
            groupedTimestamps[event.triggerName, default: []].append(event.timestamp)
        }

        return grouped.compactMap { name, risks in
            guard risks.count >= 2 else { return nil }
            let mean = average(risks)
            let score = mean - baselineRisk
            let dispersion = max(0.05, standardDeviation(risks))
            let support = risks.count
            let confidence = max(0, min(0.98, (abs(score) / dispersion) * sqrt(Double(support) / 10.0)))
            let timestamps = groupedTimestamps[name] ?? []
            guard let start = timestamps.min(), let end = timestamps.max() else { return nil }

            return TriggerAttribution(
                triggerName: name,
                score: score,
                confidence: confidence,
                evidenceWindowStart: start,
                evidenceWindowEnd: end,
                supportingEvents: support
            )
        }
        .sorted {
            if abs($0.score - $1.score) > 0.0001 {
                return $0.score > $1.score
            }
            return $0.confidence > $1.confidence
        }
        .prefix(topK)
        .map { $0 }
    }

    static func rank(entries: [MoodEntry], topK: Int = 3) -> [TriggerAttribution] {
        let vectors = FeatureStoreService.buildVectors(entries: entries)
        let events = entries.flatMap { entry in
            entry.triggerEvents.compactMap { event -> TriggerSignalEvent? in
                guard let name = event.trigger?.name, !name.isEmpty else { return nil }
                return TriggerSignalEvent(timestamp: event.timestamp, triggerName: name, intensity: event.intensity)
            }
        }
        return rank(vectors: vectors, triggerEvents: events, topK: topK)
    }

    private static func riskScore(_ vector: TemporalFeatureVector) -> Double {
        let moodRisk = abs(vector.moodLevel) / 3.0
        let sleepRisk = max(0, (6.5 - vector.sleepHours) / 3.0)
        let activationRisk = max(0, (vector.energy - 3.0) / 2.0)
        let anxietyRisk = vector.anxiety / 3.0
        let volatilityRisk = (vector.volatility7d ?? 0.5) / 1.5
        return (0.35 * moodRisk) + (0.2 * sleepRisk) + (0.15 * activationRisk) + (0.2 * anxietyRisk) + (0.1 * volatilityRisk)
    }

    private static func nearestVector(to timestamp: Date, vectors: [TemporalFeatureVector]) -> TemporalFeatureVector? {
        vectors.min(by: { abs($0.timestamp.timeIntervalSince(timestamp)) < abs($1.timestamp.timeIntervalSince(timestamp)) })
    }

    private static func average(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / Double(values.count)
    }

    private static func standardDeviation(_ values: [Double]) -> Double {
        guard values.count > 1 else { return 0 }
        let mean = average(values)
        let variance = values.reduce(0) { partial, value in
            let delta = value - mean
            return partial + (delta * delta)
        } / Double(values.count - 1)
        return sqrt(variance)
    }
}
