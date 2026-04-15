import Foundation

struct InsightNarrativeCard: Equatable, Identifiable {
    let id: String
    let title: String
    let body: String
    let confidence: Double
    let evidenceWindow: String
}

enum InsightNarrativeComposer {
    static func compose(
        safety: BayesianSafetyResult,
        topAttribution: TriggerAttribution?,
        strongestProbe: DirectionalSignalProbe?,
        phenotype: [DigitalPhenotypeCard]
    ) -> [InsightNarrativeCard] {
        var cards: [InsightNarrativeCard] = []

        let evidenceWindow = "\(safety.evidence.windowStart.formatted(date: .abbreviated, time: .omitted)) - \(safety.evidence.windowEnd.formatted(date: .abbreviated, time: .omitted))"
        let safetyLine = safetyTemplate(result: safety)
        cards.append(
            InsightNarrativeCard(
                id: "safety",
                title: "Safety Outlook",
                body: SafetyCopyPolicy.sanitizeMessage(safetyLine),
                confidence: safety.confidence,
                evidenceWindow: evidenceWindow
            )
        )

        if let topAttribution {
            let line = "Your top contributor lately has been \(topAttribution.triggerName) (\(Int((topAttribution.confidence * 100).rounded()))% match)."
            cards.append(
                InsightNarrativeCard(
                    id: "trigger",
                    title: "Trigger Pattern",
                    body: SafetyCopyPolicy.sanitizeMessage(line),
                    confidence: topAttribution.confidence,
                    evidenceWindow: "\(topAttribution.evidenceWindowStart.formatted(date: .abbreviated, time: .omitted)) - \(topAttribution.evidenceWindowEnd.formatted(date: .abbreviated, time: .omitted))"
                )
            )
        }

        if let strongestProbe {
            let direction = strongestProbe.strength >= 0 ? "tracks with higher" : "tracks with lower"
            let line = "\(strongestProbe.source) \(direction) \(strongestProbe.target) after ~\(strongestProbe.lagDays) day."
            cards.append(
                InsightNarrativeCard(
                    id: "directional",
                    title: "Directional Hint",
                    body: SafetyCopyPolicy.sanitizeMessage("\(line) \(strongestProbe.caveat)"),
                    confidence: strongestProbe.confidence,
                    evidenceWindow: evidenceWindow
                )
            )
        }

        if let sleepCard = phenotype.first(where: { $0.id == "sleep-regularity" }) {
            let line = "Your sleep regularity is \(sleepCard.interpretationBand.lowercased()) right now."
            cards.append(
                InsightNarrativeCard(
                    id: "phenotype",
                    title: "Phenotype Summary",
                    body: SafetyCopyPolicy.sanitizeMessage(line),
                    confidence: max(0.2, 1.0 - sleepCard.uncertainty),
                    evidenceWindow: evidenceWindow
                )
            )
        }

        return cards
    }

    private static func safetyTemplate(result: BayesianSafetyResult) -> String {
        switch result.severity {
        case .none:
            return "Things look okay right now. Keep logging — it helps the picture stay clear."
        case .elevated:
            return "Some things in your pattern are worth watching. Check your safety plan and log again soon."
        case .high:
            return "Your recent pattern has us concerned. Reach out to someone you trust today."
        case .critical:
            return "This looks serious. Please contact your support network or emergency help now."
        }
    }
}
