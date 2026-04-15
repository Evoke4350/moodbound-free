import Foundation

struct ModelEvidence: Equatable {
    let windowStart: Date
    let windowEnd: Date
    let signals: [String]
}

struct BayesianSafetyResult: Equatable {
    let severity: SafetySeverity
    let posteriorRisk: Double
    let confidence: Double
    let evidence: ModelEvidence
    let recommendedActions: [String]
    let messages: [String]
}

enum BayesianSafetyEngine {
    static let modelVersion = 1

    static func assess(
        vectors: [TemporalFeatureVector],
        latentResult: LatentStateResult,
        changePoints: [ChangePointEvent],
        forecast: ProbabilisticScore,
        bayesianChangeProbability: Double = 0,
        wassersteinDriftScore: Double = 0
    ) -> BayesianSafetyResult {
        let sorted = vectors.sorted { $0.timestamp < $1.timestamp }
        guard let first = sorted.first, let last = sorted.last else {
            return BayesianSafetyResult(
                severity: .none,
                posteriorRisk: 0,
                confidence: 0,
                evidence: ModelEvidence(windowStart: Date(), windowEnd: Date(), signals: []),
                recommendedActions: [],
                messages: []
            )
        }

        let recent = Array(sorted.suffix(14))
        let lowSleepRate = fraction(recent.map { $0.sleepHours < 6.0 })
        let highVolatilityRate = fraction(recent.map { ($0.volatility7d ?? 0) >= 1.1 })

        // HealthKit-derived signals
        let lowHRVRate = fraction(recent.compactMap { v -> Bool? in
            guard let hrv = v.hrvSDNN else { return nil }
            return hrv < 25
        })
        let elevatedHRRate = fraction(recent.compactMap { v -> Bool? in
            guard let hr = v.restingHeartRate else { return nil }
            return hr > 85
        })
        let lowActivityRate = fraction(recent.compactMap { v -> Bool? in
            guard let steps = v.stepCount else { return nil }
            return steps < 2000
        })

        let latentRecent = latentResult.posteriors.suffix(14)
        let elevatedPosterior = average(latentRecent.map { $0.distribution.elevated })
        let depressivePosterior = average(latentRecent.map { $0.distribution.depressive })

        let changeRate = min(1.0, Double(changePoints.count) / max(1.0, Double(recent.count) / 4.0))

        let prior = 0.22
        let priorOdds = prior / (1.0 - prior)
        var logLR = 0.0
        logLR += 2.0 * forecast.value
        logLR += 1.6 * elevatedPosterior
        logLR += 1.6 * depressivePosterior
        logLR += 1.2 * lowSleepRate
        logLR += 0.9 * highVolatilityRate
        logLR += 0.9 * changeRate
        logLR += 1.3 * bayesianChangeProbability
        logLR += 0.8 * min(1.0, wassersteinDriftScore / 0.25)
        logLR += 0.7 * lowHRVRate
        logLR += 0.5 * elevatedHRRate
        logLR += 0.6 * lowActivityRate
        logLR -= 2.1
        let likelihoodRatio = exp(logLR)

        let posteriorOdds = priorOdds * likelihoodRatio
        let posteriorRisk = posteriorOdds / (1.0 + posteriorOdds)

        let severity: SafetySeverity
        switch posteriorRisk {
        case 0.80...:
            severity = .critical
        case 0.62...:
            severity = .high
        case 0.42...:
            severity = .elevated
        default:
            severity = .none
        }

        var signals: [String] = []
        if forecast.value >= 0.6 {
            signals.append("Your week ahead looks bumpier than usual.")
        }
        if elevatedPosterior >= 0.45 {
            signals.append("Your recent pattern is leaning toward the high end.")
        }
        if depressivePosterior >= 0.45 {
            signals.append("Your recent pattern is leaning toward the low end.")
        }
        if lowSleepRate >= 0.3 {
            signals.append("You've had several short sleep nights recently.")
        }
        if highVolatilityRate >= 0.35 {
            signals.append("Your mood has been swinging more than usual.")
        }
        if !changePoints.isEmpty {
            signals.append("There's been a noticeable shift in your pattern recently.")
        }
        if bayesianChangeProbability >= 0.25 {
            signals.append("Things seem to be shifting — worth paying attention to.")
        }
        if wassersteinDriftScore >= 0.22 {
            signals.append("Your recent days look different from your usual pattern.")
        }
        if lowHRVRate >= 0.3 {
            signals.append("Your heart rate variability has been low — your body may be under stress.")
        }
        if lowActivityRate >= 0.4 {
            signals.append("Your activity has been unusually low recently.")
        }

        let recommendedActions: [String]
        switch severity {
        case .none:
            recommendedActions = []
        case .elevated:
            recommendedActions = ["Review your safety plan", "Log another check-in today"]
        case .high:
            recommendedActions = ["Contact a support person", "Message your care team today"]
        case .critical:
            recommendedActions = ["Contact emergency support now", "Stay with a trusted person if possible"]
        }

        let confidence = max(0, min(1, (1.0 - forecast.calibrationError) * min(1.0, Double(recent.count) / 14.0)))

        return BayesianSafetyResult(
            severity: severity,
            posteriorRisk: posteriorRisk,
            confidence: confidence,
            evidence: ModelEvidence(
                windowStart: first.timestamp,
                windowEnd: last.timestamp,
                signals: signals
            ),
            recommendedActions: recommendedActions,
            messages: SafetyCopyPolicy.sanitize(signals)
        )
    }

    private static func average(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / Double(values.count)
    }

    private static func fraction(_ bools: [Bool]) -> Double {
        guard !bools.isEmpty else { return 0 }
        return Double(bools.filter { $0 }.count) / Double(bools.count)
    }
}
