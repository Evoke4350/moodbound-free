import Foundation

enum SafetySeverity: String {
    case none = "None"
    case elevated = "Elevated"
    case high = "High"
    case critical = "Critical"
}

struct SafetyAssessment {
    var severity: SafetySeverity
    var messages: [String]
    var recommendedActions: [String]
    var confidence: Double
    var crisisBannerText: String?
    var posteriorRisk: Double
    var evidenceSignals: [String]
    var evidenceWindowStart: Date?
    var evidenceWindowEnd: Date?
}

struct InsightSnapshot {
    var streakDays: Int
    var avg7: Double?
    var avg30: Double?
    var lowSleepCount14d: Int
    var highSleepCount14d: Int
    var medicationAdherenceRate14d: Double?
    var topTrigger14d: String?
    var safety: SafetyAssessment
    var directionalProbes: [DirectionalSignalProbe]
    var triggerAttributions: [TriggerAttribution]
    var medicationTrajectories: [MedicationTrajectory]
    var adaptivePrompts: [AdaptivePrompt]
    var phenotypeCards: [DigitalPhenotypeCard]
    var narrativeCards: [InsightNarrativeCard]
    var modelHealth: ModelHealthStatus
    var bayesianChangeProbability: Double
    var wassersteinDriftScore: Double
    var conformalCIWidth: Double
    // B1: Full conformalized forecast point estimate + CI, so views can render
    // uncertainty as a dedicated outlook card rather than just a categorical label.
    var forecastValue: Double
    var forecastCILow: Double
    var forecastCIHigh: Double
    // B2: Per-day latent state posteriors, so HistoryView can overlay a
    // dominant-state background on the mood chart.
    var latentPosteriors: [LatentStateDayPosterior]
    var weatherCity: String?
    var weatherCoverageDays: Int
    var rainyMoodDelta: Double?
    var hotMoodDelta: Double?
}

enum InsightEngine {
    static func snapshot(entries: [MoodEntry], now: Date) -> InsightSnapshot {
        let viewModel = MoodViewModel()
        let recent14 = viewModel.entriesWithinDays(entries: entries, days: 14, now: now)

        let lowSleepCount = recent14.filter { $0.sleepHours < 6 }.count
        let highSleepCount = recent14.filter { $0.sleepHours > 10 }.count
        let features = FeatureStoreService.buildVectors(entries: entries)
        let latent = LatentStateService.inferStates(vectors: features)
        let changePoints = ChangePointService.detect(vectors: features)
        let rawForecast = RiskForecastService.forecast7dRisk(vectors: features)
        let forecast = ConformalCalibrationService.conformalize(raw: rawForecast, vectors: features)
        let bocpd = BayesianOnlineChangePointService.detect(vectors: features)
        let wasserstein = WassersteinDriftService.assess(vectors: features)
        let bayesian = BayesianSafetyEngine.assess(
            vectors: features,
            latentResult: latent,
            changePoints: changePoints,
            forecast: forecast,
            bayesianChangeProbability: bocpd.latestChangeProbability,
            wassersteinDriftScore: wasserstein.score
        )
        let safety = safetyAssessment(from: bayesian)
        let directional = DirectionalSignalService.probes(vectors: features)
        let attributions = TriggerAttributionService.rank(entries: entries, topK: 3)
        let trajectories = MedicationTrajectoryService.trajectories(entries: entries)
        let adaptivePrompts = AdaptiveCheckinService.nextPrompts(
            entries: entries,
            vectors: features,
            forecast: forecast,
            attributions: attributions
        )
        let phenotype = DigitalPhenotypeService.cards(vectors: features)
        let narratives = InsightNarrativeComposer.compose(
            safety: bayesian,
            topAttribution: attributions.first,
            strongestProbe: directional.first,
            phenotype: phenotype
        )
        let health = ModelHealthService.assess(vectors: features, forecast: forecast, now: now)
        let weather = weatherSummary(entries: entries)

        return InsightSnapshot(
            streakDays: viewModel.streakDays(entries: entries, now: now),
            avg7: viewModel.averageMood(entries: entries, days: 7, now: now),
            avg30: viewModel.averageMood(entries: entries, days: 30, now: now),
            lowSleepCount14d: lowSleepCount,
            highSleepCount14d: highSleepCount,
            medicationAdherenceRate14d: medicationAdherenceRate(entries: recent14),
            topTrigger14d: topTrigger(entries: recent14),
            safety: safety,
            directionalProbes: directional,
            triggerAttributions: attributions,
            medicationTrajectories: trajectories,
            adaptivePrompts: adaptivePrompts,
            phenotypeCards: phenotype,
            narrativeCards: narratives,
            modelHealth: health,
            bayesianChangeProbability: bocpd.latestChangeProbability,
            wassersteinDriftScore: wasserstein.score,
            conformalCIWidth: forecast.ciWidth,
            forecastValue: forecast.value,
            forecastCILow: forecast.ciLow,
            forecastCIHigh: forecast.ciHigh,
            latentPosteriors: latent.posteriors,
            weatherCity: weather.city,
            weatherCoverageDays: weather.coverageDays,
            rainyMoodDelta: weather.rainyMoodDelta,
            hotMoodDelta: weather.hotMoodDelta
        )
    }

    static func trendDescription(_ avg: Double) -> String {
        switch avg {
        case ..<(-1.5): return "Consistently low. Stay close to people who support you."
        case -1.5..<(-0.5): return "A bit low lately. Worth keeping an eye on."
        case -0.5...0.5: return "Holding steady."
        case 0.5...1.5: return "Running a little high. Notice how your sleep and energy feel."
        default: return "Running quite high. It might be a good time to check in with your care team."
        }
    }

    private static func medicationAdherenceRate(entries: [MoodEntry]) -> Double? {
        let events = entries.flatMap(\.medicationAdherenceEvents)
        guard !events.isEmpty else { return nil }
        let taken = events.filter(\.taken).count
        return Double(taken) / Double(events.count)
    }

    private static func topTrigger(entries: [MoodEntry]) -> String? {
        let names = entries
            .flatMap(\.triggerEvents)
            .compactMap { $0.trigger?.name.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !names.isEmpty else { return nil }
        let counts = Dictionary(grouping: names, by: { $0 }).mapValues(\.count)
        return counts.max(by: { $0.value < $1.value })?.key
    }

    private static func safetyAssessment(from bayesian: BayesianSafetyResult) -> SafetyAssessment {
        return SafetyAssessment(
            severity: bayesian.severity,
            messages: bayesian.messages,
            recommendedActions: bayesian.recommendedActions,
            confidence: bayesian.confidence,
            crisisBannerText: SafetyCopyPolicy.crisisBannerText(for: bayesian.severity),
            posteriorRisk: bayesian.posteriorRisk,
            evidenceSignals: bayesian.evidence.signals,
            evidenceWindowStart: bayesian.evidence.windowStart,
            evidenceWindowEnd: bayesian.evidence.windowEnd
        )
    }

    // WMO codes that the WeatherKit-backed service can actually emit and that
    // mean "wet" for the purposes of mood comparison. The previous list was
    // copied from a former Open-Meteo backend and contained codes (63, 80–82,
    // 96, 99) the app never produces, while excluding drizzle (51, 56),
    // freezing rain (66), and sleet (67) — silently dropping those days from
    // the comparison.
    private static let rainyWeatherCodes: Set<Int> = [51, 56, 61, 65, 66, 67, 95, 96]
    // Clear-ish sky codes: clear, mostly clear, partly cloudy.
    private static let clearWeatherCodes: Set<Int> = [0, 1, 2]

    private static func weatherSummary(entries: [MoodEntry]) -> (city: String?, coverageDays: Int, rainyMoodDelta: Double?, hotMoodDelta: Double?) {
        let weatherEntries = entries.filter { $0.weatherCode != nil && $0.temperatureC != nil }
        guard !weatherEntries.isEmpty else { return (nil, 0, nil, nil) }

        let rainy = weatherEntries.filter {
            ($0.precipitationMM ?? 0) >= 1 || rainyWeatherCodes.contains($0.weatherCode ?? -1)
        }
        let clear = weatherEntries.filter {
            ($0.precipitationMM ?? 0) < 0.5 && clearWeatherCodes.contains($0.weatherCode ?? -1)
        }
        let rainyDelta: Double? = {
            guard !rainy.isEmpty, !clear.isEmpty else { return nil }
            let rainyAvg = Double(rainy.reduce(0) { $0 + $1.moodLevel }) / Double(rainy.count)
            let clearAvg = Double(clear.reduce(0) { $0 + $1.moodLevel }) / Double(clear.count)
            return rainyAvg - clearAvg
        }()

        let hot = weatherEntries.filter { ($0.temperatureC ?? 0) >= 27 }
        let mild = weatherEntries.filter { (15...24).contains($0.temperatureC ?? -1000) }
        let hotDelta: Double? = {
            guard !hot.isEmpty, !mild.isEmpty else { return nil }
            let hotAvg = Double(hot.reduce(0) { $0 + $1.moodLevel }) / Double(hot.count)
            let mildAvg = Double(mild.reduce(0) { $0 + $1.moodLevel }) / Double(mild.count)
            return hotAvg - mildAvg
        }()

        // Skip placeholders that older builds may have persisted as a literal
        // city name when reverse geocoding failed.
        let city = weatherEntries
            .compactMap(\.weatherCity)
            .first { !$0.isEmpty && $0.caseInsensitiveCompare("Unknown") != .orderedSame }
        return (city, weatherEntries.count, rainyDelta, hotDelta)
    }
}
