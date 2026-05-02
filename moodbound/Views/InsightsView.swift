import SwiftUI
import SwiftData

struct InsightsView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Query(sort: \MoodEntry.timestamp, order: .reverse) private var entries: [MoodEntry]
    @State private var showingSafetyPlan = false
    @State private var showingLifeChart = false
    @AppStorage(AppClock.overrideTimestampKey) private var overrideTimestamp: Double = 0

    var body: some View {
        NavigationStack {
            ScrollView {
                if entries.count < 3 {
                    ContentUnavailableView(
                        "Need more data",
                        systemImage: "brain.head.profile",
                        description: Text("Log at least 3 entries to see insights")
                    )
                } else {
                    insightLayout
                        .padding(.horizontal, horizontalSizeClass == .regular ? 24 : 16)
                        .padding(.vertical, 16)
                        .frame(maxWidth: horizontalSizeClass == .regular ? 980 : .infinity)
                        .frame(maxWidth: .infinity)
                }
            }
            .navigationTitle("Insights")
            .sheet(isPresented: $showingSafetyPlan) {
                SafetyPlanView()
            }
            .sheet(isPresented: $showingLifeChart) {
                LifeChartView()
            }
        }
        .animation(.smooth(duration: 0.3), value: entries.count)
    }

    @ViewBuilder
    private var insightLayout: some View {
        if horizontalSizeClass == .regular {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                topCards
            }
        } else {
            VStack(spacing: 12) {
                topCards
            }
        }
    }

    @ViewBuilder
    private var topCards: some View {
        let snapshot = InsightEngine.snapshot(entries: entries, now: appNow)

        outlookCard(snapshot: snapshot)
        coursePatternCard(snapshot: snapshot)

        insightCard(
            icon: "flame.fill",
            color: .orange,
            title: "Streak",
            value: "\(snapshot.streakDays) day\(snapshot.streakDays == 1 ? "" : "s")"
        )

        if let avg7 = snapshot.avg7 {
            insightCard(
                icon: "chart.line.uptrend.xyaxis",
                color: MoodboundDesign.tint,
                title: "7-Day Average",
                value: String(format: "%+.1f", avg7),
                detail: InsightEngine.trendDescription(avg7)
            )
        }

        if let avg30 = snapshot.avg30 {
            insightCard(
                icon: "calendar",
                color: .blue,
                title: "30-Day Average",
                value: String(format: "%+.1f", avg30),
                detail: InsightEngine.trendDescription(avg30)
            )
        }

        if snapshot.lowSleepCount14d > 0 || snapshot.highSleepCount14d > 0 {
            sleepInsight(snapshot: snapshot)
        }

        if let adherence = snapshot.medicationAdherenceRate14d {
            insightCard(
                icon: "pills.fill",
                color: .mint,
                title: "Medication Adherence (14d)",
                value: "\(Int((adherence * 100).rounded()))%",
                detail: "Based on logged medication events."
            )
        }

        if let topTrigger = snapshot.topTrigger14d {
            insightCard(
                icon: "bolt.heart.fill",
                color: .pink,
                title: "Top Trigger (14d)",
                value: topTrigger,
                detail: "Most frequently tagged contributing factor."
            )
        }

        yourPatternsCard(snapshot: snapshot)
        monthOverMonthCard
        if snapshot.weatherCoverageDays >= 7 {
            weatherImpactCard(snapshot: snapshot)
        }
        if snapshot.safety.severity != .none {
            warningCard(snapshot: snapshot)
        }
        safetyPlanCard
        modelTransparencyCard(snapshot: snapshot)
        phenotypeCard(snapshot: snapshot)
        if let probe = snapshot.directionalProbes.first, probe.confidence > 0 {
            directionalCard(snapshot: snapshot, probe: probe)
        }
        if let topTrigger = snapshot.triggerAttributions.first {
            triggerAttributionCard(snapshot: snapshot, top: topTrigger)
        }
        if let trajectory = snapshot.medicationTrajectories.first(where: \.isDataSufficient) {
            medicationTrajectoryCard(snapshot: snapshot, trajectory: trajectory)
        }
        if !snapshot.adaptivePrompts.isEmpty {
            adaptivePromptCard(snapshot: snapshot)
        }
        if !snapshot.narrativeCards.isEmpty {
            narrativeCard(snapshot: snapshot)
        }
    }

    private func insightCard(icon: String, color: Color, title: String, value: String, detail: String? = nil) -> some View {
        HStack {
            Image(systemName: icon)
                .font(.title)
                .foregroundStyle(color)
                .frame(width: 50)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.title2)
                    .fontWeight(.bold)
                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()
        }
        .moodCard()
        .transition(.opacity.combined(with: .scale(scale: 0.98)))
    }

    private func sleepInsight(snapshot: InsightSnapshot) -> some View {
        insightCard(
            icon: "moon.fill",
            color: .indigo,
            title: "Sleep Pattern (14d)",
            value: snapshot.lowSleepCount14d > 0 ? "Under-sleeping" : "Over-sleeping",
            detail: sleepDetail(lowSleep: snapshot.lowSleepCount14d, highSleep: snapshot.highSleepCount14d)
        )
    }

    private func sleepDetail(lowSleep: Int, highSleep: Int) -> String {
        if lowSleep > 0 && highSleep > 0 {
            return "Irregular sleep — \(lowSleep) short nights, \(highSleep) long nights in 2 weeks"
        } else if lowSleep > 0 {
            return "\(lowSleep) nights under 6h in the last 2 weeks. Low sleep can trigger episodes."
        } else {
            return "\(highSleep) nights over 10h in the last 2 weeks. Oversleeping can be a sign things are off."
        }
    }

    private func warningCard(snapshot: InsightSnapshot) -> some View {
        let safety = snapshot.safety
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(MoodboundDesign.accent)
                Text("Safety: \(safety.severity.rawValue)")
                    .font(.headline)
            }

            ForEach(safety.messages, id: \.self) { message in
                Text(message)
                    .font(.subheadline)
            }

            if !safety.recommendedActions.isEmpty {
                Text("Recommended actions")
                    .font(.subheadline.weight(.semibold))
                    .padding(.top, 4)
                ForEach(safety.recommendedActions, id: \.self) { action in
                    Text("• \(action)")
                        .font(.subheadline)
                }
            }

            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Concern Level")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(concernLabel(safety.posteriorRisk))
                        .font(.headline.weight(.bold))
                        .foregroundStyle(MoodboundDesign.accent)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Data Confidence")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(confidenceLabel(safety.confidence))
                        .font(.headline.weight(.bold))
                        .foregroundStyle(MoodboundDesign.tint)
                }
            }

            if let start = safety.evidenceWindowStart, let end = safety.evidenceWindowEnd {
                Text("Based on \(start.formatted(date: .abbreviated, time: .omitted)) – \(end.formatted(date: .abbreviated, time: .omitted))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if !safety.evidenceSignals.isEmpty {
                Text("Evidence")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                ForEach(safety.evidenceSignals.prefix(3), id: \.self) { signal in
                    Text("• \(signal)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let crisisText = safety.crisisBannerText {
                Text(crisisText)
                    .font(.subheadline)
                    .fontWeight(.semibold)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .moodCard()
    }

    @ViewBuilder
    private var monthOverMonthCard: some View {
        let calendar = Calendar.current
        let now = appNow

        // Split entries into two equal-length 30-day windows anchored on
        // calendar day boundaries. The previous implementation used wall-clock
        // subtraction (`now - 30d`, `now - 60d`) and an inclusive upper bound
        // for this-month, which made this-month a 31-day window while
        // last-month was 30 — biasing the comparison.
        let startToday = calendar.startOfDay(for: now)
        let upperThis = calendar.date(byAdding: .day, value: 1, to: startToday) ?? startToday
        let lowerThis = calendar.date(byAdding: .day, value: -29, to: startToday) ?? startToday
        let lowerLast = calendar.date(byAdding: .day, value: -59, to: startToday) ?? startToday
        let thisMonth = entries.filter { $0.timestamp >= lowerThis && $0.timestamp < upperThis }
        let lastMonth = entries.filter { $0.timestamp >= lowerLast && $0.timestamp < lowerThis }

        if thisMonth.count >= 5 && lastMonth.count >= 5 {
            let thisAvg = Double(thisMonth.reduce(0) { $0 + $1.moodLevel }) / Double(thisMonth.count)
            let lastAvg = Double(lastMonth.reduce(0) { $0 + $1.moodLevel }) / Double(lastMonth.count)
            let delta = thisAvg - lastAvg

            // sleepHours == 0 is the "unknown" sentinel; exclude those entries
            // so users who skipped logging sleep don't drag their monthly
            // average to absurd values.
            let thisSleepKnown = thisMonth.map(\.sleepHours).filter { $0 > 0 }
            let lastSleepKnown = lastMonth.map(\.sleepHours).filter { $0 > 0 }
            let thisSleep = thisSleepKnown.isEmpty
                ? nil
                : thisSleepKnown.reduce(0.0, +) / Double(thisSleepKnown.count)
            let lastSleep = lastSleepKnown.isEmpty
                ? nil
                : lastSleepKnown.reduce(0.0, +) / Double(lastSleepKnown.count)
            let sleepDelta: Double? = (thisSleep != nil && lastSleep != nil) ? (thisSleep! - lastSleep!) : nil

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "calendar.badge.clock")
                        .foregroundStyle(.blue)
                    Text("This Month vs Last")
                        .font(.headline)
                }

                HStack(spacing: 20) {
                    comparisonStat(
                        label: "Avg Mood",
                        delta: delta,
                        format: { String(format: "%+.1f", $0) }
                    )
                    if let sleepDelta {
                        comparisonStat(
                            label: "Avg Sleep",
                            delta: sleepDelta,
                            format: { String(format: "%+.1fh", $0) }
                        )
                    }
                    comparisonStat(
                        label: "Entries",
                        delta: Double(thisMonth.count - lastMonth.count),
                        format: { String(format: "%+.0f", $0) }
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .moodCard()
        }
    }

    private func comparisonStat(label: String, delta: Double, format: (Double) -> String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 2) {
                Image(systemName: delta > 0.05 ? "arrow.up.right" : delta < -0.05 ? "arrow.down.right" : "arrow.right")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(comparisonColor(delta))
                Text(format(delta))
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(comparisonColor(delta))
            }
        }
    }

    private func comparisonColor(_ delta: Double) -> Color {
        if abs(delta) < 0.05 { return .secondary }
        return delta > 0 ? .green : .orange
    }

    @ViewBuilder
    private func yourPatternsCard(snapshot: InsightSnapshot) -> some View {
        let stories = patternStories(snapshot: snapshot)
        if !stories.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "sparkle.magnifyingglass")
                        .foregroundStyle(MoodboundDesign.tint)
                    Text("Your Patterns")
                        .font(.headline)
                }

                ForEach(stories, id: \.self) { story in
                    Text(story)
                        .font(.subheadline)
                }

                Text("Based on your logged data — patterns, not diagnoses.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .moodCard()
        }
    }

    // Map the jargon labels from DirectionalSignalService into natural prose.
    private static let friendlyProbeLabels: [String: String] = [
        "Sleep Deficit": "sleep drops",
        "Next-Day Mood Elevation": "mood shifts upward",
        "Trigger Load": "trigger load rises",
        "Next-Day Anxiety": "anxiety increases",
        "Medication Adherence": "you take your meds consistently",
        "Next-Day Volatility (inverse)": "your stability improves",
    ]

    private func patternStories(snapshot: InsightSnapshot) -> [String] {
        var stories: [String] = []

        // Directional signal: "When your sleep drops, your mood tends to shift upward ~1 day later."
        if let probe = snapshot.directionalProbes.first, probe.confidence >= 0.3 {
            let source = Self.friendlyProbeLabels[probe.source] ?? probe.source.lowercased()
            let target = Self.friendlyProbeLabels[probe.target] ?? probe.target.lowercased()
            stories.append("When your \(source), your \(target) about \(probe.lagDays) day\(probe.lagDays == 1 ? "" : "s") later.")
        }

        // Top trigger: "X is your strongest mood-affecting trigger."
        if let trigger = snapshot.triggerAttributions.first {
            let direction = trigger.score > 0 ? "raising" : "lowering"
            stories.append("\(trigger.triggerName) is your strongest trigger, \(direction) your mood when it shows up.")
        }

        // Medication trajectory
        if let med = snapshot.medicationTrajectories.first(where: \.isDataSufficient) {
            if med.shortWindowDelta < -0.1 {
                stories.append("\(med.medicationName) seems to be helping — your stability is better on days you take it.")
            } else if med.shortWindowDelta > 0.1 {
                stories.append("\(med.medicationName) doesn't show a clear benefit yet in your data.")
            }
        }

        // Sleep regularity from phenotype
        if let sleepCard = snapshot.phenotypeCards.first(where: { $0.title.localizedCaseInsensitiveContains("sleep") }),
           sleepCard.isSufficientData {
            stories.append("Your sleep regularity is \(sleepCard.interpretationBand.lowercased()) right now.")
        }

        return stories
    }

    private var safetyPlanCard: some View {
        Button {
            showingSafetyPlan = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "cross.case.fill")
                    .font(.title3)
                    .foregroundStyle(.red.opacity(0.85))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Safety Plan")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text("Your warning signs, coping strategies, and contacts")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .accessibilityIdentifier("open-safety-plan-button")
        .moodCard()
    }

    private func weatherImpactCard(snapshot: InsightSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Weather & Mood")
                .font(.headline)
            Text("\(snapshot.weatherCoverageDays)-day weather timeline\(snapshot.weatherCity.map { " for \($0)" } ?? "")")
                .font(.caption)
                .foregroundStyle(.secondary)

            if let rainyDelta = snapshot.rainyMoodDelta {
                HStack(spacing: 8) {
                    Text("🌧")
                        .font(.title2)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(weatherEffectLabel("Rain", delta: rainyDelta))
                            .font(.subheadline.weight(.bold))
                        Text(rainyDelta < -0.3
                             ? "Your mood tends to dip on rainy days."
                             : rainyDelta > 0.3
                             ? "Rain actually seems to help your mood."
                             : "Rainy days don't seem to affect you much.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                weatherGatheringHint("rain vs. clear sky")
            }

            if let hotDelta = snapshot.hotMoodDelta {
                HStack(spacing: 8) {
                    Text("🌡️")
                        .font(.title2)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(weatherEffectLabel("Heat", delta: hotDelta))
                            .font(.subheadline.weight(.bold))
                        Text(hotDelta > 0.3
                             ? "Hot days seem to amp you up a bit."
                             : hotDelta < -0.3
                             ? "Heat tends to bring your mood down."
                             : "Heat doesn't seem to affect your mood much.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                weatherGatheringHint("hot vs. mild days")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .moodCard()
    }

    private func weatherGatheringHint(_ comparison: String) -> some View {
        HStack(spacing: 8) {
            Text("📊")
                .font(.title2)
            Text("Log a few more entries in different weather to see how \(comparison) affect your mood.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func outlookCard(snapshot: InsightSnapshot) -> some View {
        let score = outlookScore(snapshot: snapshot)
        let band = outlookBand(for: score, evidenceLevel: snapshot.evidenceLevel)

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("How's It Looking")
                    .font(.headline)
                Spacer()
                Text(band.label)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(band.color.opacity(0.14))
                    .foregroundStyle(band.color)
                    .clipShape(Capsule())
            }

            Text(stabilityLabel(score: score, evidenceLevel: snapshot.evidenceLevel))
                .font(.title3.weight(.bold))

            outcomeMeter(score: score, color: band.color)

            Text(outlookSummary(snapshot: snapshot, score: score))
                .font(.subheadline)

            Text("This is a personal tracking tool, not a diagnosis.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .moodCard()
    }

    private func coursePatternCard(snapshot: InsightSnapshot) -> some View {
        let phase = currentPhase(snapshot: snapshot)
        let instability = instabilityIndex(snapshot: snapshot)
        // Show "Mixed features" only when there's sustained DSM-aligned
        // signal: at least 3 days in the last 14 with concurrent depressive
        // + activation markers (or activated + dysphoric markers). The old
        // mixedFeaturesRisk fired off sleep variance + change probability,
        // which made the pill stick on for almost every active user.
        let showMixed = snapshot.evidenceLevel != .insufficient
            && snapshot.mixedFeatureDays14d >= 3

        return VStack(alignment: .leading, spacing: 12) {
            Text("Where You're At")
                .font(.headline)

            HStack(spacing: 8) {
                phasePill(title: phase.title, color: phase.color)
                if showMixed {
                    phasePill(title: "Mixed features", color: .purple)
                }
                if instability >= 0.3 {
                    phasePill(title: "Choppy", color: .orange)
                }
            }

            Text(phase.description)
                .font(.subheadline)

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Chance of Shift")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(shiftChanceLabel(snapshot.bayesianChangeProbability))
                        .font(.headline.weight(.bold))
                        .foregroundStyle(shiftChanceColor(snapshot.bayesianChangeProbability))
                }
                Spacer()
                VStack(alignment: .leading, spacing: 2) {
                    Text("Data Confidence")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(confidenceLabel(snapshot.safety.confidence))
                        .font(.headline.weight(.bold))
                        .foregroundStyle(MoodboundDesign.tint)
                }
                Spacer()
                VStack(alignment: .leading, spacing: 2) {
                    Text("Predictability")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(predictabilityLabel(snapshot.conformalCIWidth))
                        .font(.caption.weight(.bold))
                        .foregroundStyle(predictabilityColor(snapshot.conformalCIWidth))
                }
            }

            Text(L10n.tr("insights.data_confidence.tooltip"))
                .font(.caption2)
                .foregroundStyle(.secondary)

            Button {
                showingLifeChart = true
            } label: {
                Label("Open life chart", systemImage: "chart.bar.xaxis")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("open-life-chart-button")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .moodCard()
    }

    private func shiftChanceLabel(_ probability: Double) -> String {
        let pct = Int((probability * 100).rounded())
        if pct < 15 { return "Low (\(pct)%)" }
        if pct < 40 { return "Moderate (\(pct)%)" }
        return "High (\(pct)%)"
    }

    private func shiftChanceColor(_ probability: Double) -> Color {
        if probability < 0.15 { return .green }
        if probability < 0.4 { return .orange }
        return .red
    }

    private func confidenceLabel(_ confidence: Double) -> String {
        let pct = Int((confidence * 100).rounded())
        if pct >= 80 { return "High (\(pct)%)" }
        if pct >= 50 { return "Moderate (\(pct)%)" }
        return "Low (\(pct)%)"
    }

    private func modelTransparencyCard(snapshot: InsightSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("How This Works")
                .font(.headline)

            Text("Overall picture")
                .font(.subheadline.weight(.semibold))
            Text("We combine your sleep, mood, energy, and medication data into one score.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Divider()

            Text("Pattern change")
                .font(.subheadline.weight(.semibold))
            Text(driftLabel(snapshot.wassersteinDriftScore))
                .font(.subheadline.weight(.bold))
                .foregroundStyle(driftColor(snapshot.wassersteinDriftScore))
            Text("How different your recent days look compared to your usual.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Divider()

            Text("How predictable things are")
                .font(.subheadline.weight(.semibold))
            Text(predictabilityLabel(snapshot.conformalCIWidth))
                .font(.subheadline.weight(.bold))
                .foregroundStyle(predictabilityColor(snapshot.conformalCIWidth))
            Text("How confident we are about what comes next based on your history.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .moodCard()
    }

    private func driftLabel(_ score: Double) -> String {
        if score < 0.15 { return "Very consistent" }
        if score < 0.3 { return "Mostly the same" }
        if score < 0.45 { return "Some changes" }
        return "Noticeably different"
    }

    private func driftColor(_ score: Double) -> Color {
        if score < 0.3 { return .green }
        if score < 0.45 { return .orange }
        return .red
    }

    private func predictabilityLabel(_ width: Double) -> String {
        if width < 1.0 { return "Very predictable" }
        if width < 2.0 { return "Fairly predictable" }
        if width < 3.0 { return "Somewhat unpredictable" }
        return "Hard to predict right now"
    }

    private func predictabilityColor(_ width: Double) -> Color {
        if width < 1.5 { return .green }
        if width < 2.5 { return .orange }
        return .red
    }

    private func phenotypeCard(snapshot: InsightSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Your Profile")
                .font(.headline)

            ForEach(snapshot.phenotypeCards) { card in
                VStack(alignment: .leading, spacing: 4) {
                    Text(friendlyPhenotypeTitle(card))
                        .font(.subheadline.weight(.semibold))
                    Text(friendlyPhenotypeValue(card))
                        .font(.title3.weight(.bold))
                        .foregroundStyle(phenotypeColor(card))
                    Text(friendlyPhenotypeExplanation(card))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if card.id != snapshot.phenotypeCards.last?.id {
                    Divider()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .moodCard()
        .accessibilityIdentifier("insights-phenotype-card")
    }

    private func friendlyPhenotypeTitle(_ card: DigitalPhenotypeCard) -> String {
        switch card.id {
        case "sleep-regularity": return "How Regular Your Sleep Is"
        case "activation-slope": return "Energy Direction"
        case "recovery-half-life": return "Bounce-Back Speed"
        default: return card.title
        }
    }

    private func friendlyPhenotypeValue(_ card: DigitalPhenotypeCard) -> String {
        guard card.isSufficientData else { return "Not enough data yet" }
        switch card.id {
        case "sleep-regularity":
            let score = Int(card.metricValue.rounded())
            if score >= 75 { return "Consistent" }
            if score >= 45 { return "Somewhat irregular" }
            return "All over the place"
        case "activation-slope":
            if card.metricValue >= 0.06 { return "Trending up" }
            if card.metricValue <= -0.06 { return "Trending down" }
            return "Holding steady"
        case "recovery-half-life":
            let days = card.metricValue
            let rounded = Int(days.rounded())
            if days <= 2 { return "Fast — about \(rounded) day\(rounded == 1 ? "" : "s")" }
            if days <= 5 { return "A few days" }
            return "Takes a while — \(rounded) days"
        default:
            return card.interpretationBand
        }
    }

    private func friendlyPhenotypeExplanation(_ card: DigitalPhenotypeCard) -> String {
        guard card.isSufficientData else { return "Keep logging to build your profile." }
        switch card.id {
        case "sleep-regularity":
            return "Consistent sleep is one of the strongest stabilizers for mood."
        case "activation-slope":
            return "Whether your energy has been rising, falling, or flat recently."
        case "recovery-half-life":
            return "How quickly you tend to bounce back after a rough patch."
        default:
            return card.interpretationBand
        }
    }

    private func phenotypeColor(_ card: DigitalPhenotypeCard) -> Color {
        guard card.isSufficientData else { return .secondary }
        switch card.id {
        case "sleep-regularity":
            if card.metricValue >= 75 { return .green }
            if card.metricValue >= 45 { return .orange }
            return .red
        case "activation-slope":
            if abs(card.metricValue) < 0.06 { return .green }
            return .orange
        case "recovery-half-life":
            if card.metricValue <= 2 { return .green }
            if card.metricValue <= 5 { return .orange }
            return .red
        default:
            return MoodboundDesign.tint
        }
    }

    private func directionalCard(snapshot: InsightSnapshot, probe: DirectionalSignalProbe) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Connection Spotted")
                .font(.headline)
            Text("\(probe.source) → \(probe.target)")
                .font(.title3.weight(.bold))

            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Strength")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(connectionStrengthLabel(probe.strength))
                        .font(.title2.weight(.bold))
                        .foregroundStyle(connectionStrengthColor(probe.strength))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Confidence")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\(Int((probe.confidence * 100).rounded()))%")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(MoodboundDesign.tint)
                }
            }

            Text("This is a pattern in your data, not a diagnosis or proof of cause and effect. Use it as a conversation starter with your care team.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .moodCard()
    }

    private func connectionStrengthLabel(_ strength: Double) -> String {
        let abs = abs(strength)
        if abs >= 0.7 { return "Strong" }
        if abs >= 0.5 { return "Moderate" }
        if abs >= 0.3 { return "Mild" }
        return "Weak"
    }

    private func connectionStrengthColor(_ strength: Double) -> Color {
        let abs = abs(strength)
        if abs >= 0.7 { return .red }
        if abs >= 0.5 { return .orange }
        return .green
    }

    private func triggerAttributionCard(snapshot: InsightSnapshot, top: TriggerAttribution) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Biggest Trigger")
                .font(.headline)
            Text(top.triggerName)
                .font(.title2.weight(.bold))
            HStack(spacing: 4) {
                Text("\(Int((top.confidence * 100).rounded()))%")
                    .font(.title.weight(.bold))
                    .foregroundStyle(MoodboundDesign.tint)
                Text("match")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Text("Based on \(top.evidenceWindowStart.formatted(date: .abbreviated, time: .omitted)) – \(top.evidenceWindowEnd.formatted(date: .abbreviated, time: .omitted))")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text("This shows which factor appeared most often alongside mood changes — it's a pattern, not a cause.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .moodCard()
    }

    private func medicationTrajectoryCard(snapshot: InsightSnapshot, trajectory: MedicationTrajectory) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Medication Effect")
                .font(.headline)
            Text(trajectory.medicationName)
                .font(.title3.weight(.bold))

            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Past few days")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(medEffectLabel(trajectory.shortWindowDelta))
                        .font(.headline.weight(.bold))
                        .foregroundStyle(medEffectColor(trajectory.shortWindowDelta))
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Past few weeks")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(medEffectLabel(trajectory.mediumWindowDelta))
                        .font(.headline.weight(.bold))
                        .foregroundStyle(medEffectColor(trajectory.mediumWindowDelta))
                }
            }

            Text("Compares your stability on days you took this medication vs. days you missed it.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .moodCard()
    }

    private func medEffectLabel(_ delta: Double) -> String {
        if delta < -0.15 { return "Helping" }
        if delta < -0.05 { return "Slightly better" }
        if delta > 0.15 { return "No clear benefit" }
        if delta > 0.05 { return "Unclear" }
        return "About the same"
    }

    private func medEffectColor(_ delta: Double) -> Color {
        if delta < -0.1 { return .green }
        if delta > 0.1 { return .orange }
        return .secondary
    }

    private func adaptivePromptCard(snapshot: InsightSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "lightbulb.fill")
                    .foregroundStyle(.yellow)
                Text("Try This Next Time")
                    .font(.headline)
            }
            Text("These questions can help fill in gaps in your data:")
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach(snapshot.adaptivePrompts.prefix(2)) { prompt in
                VStack(alignment: .leading, spacing: 4) {
                    Text(prompt.title)
                        .font(.subheadline.weight(.bold))
                    Text(prompt.prompt)
                        .font(.subheadline)
                    Text(prompt.rationale)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(MoodboundDesign.tint.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .moodCard()
    }

    /// B4: Render all narrative cards the composer produced (safety,
    /// trigger, directional, phenotype), not just the first. Each card is
    /// nil-safe — the composer only appends a card when its underlying
    /// data exists, so new users with little history will still see just
    /// the safety card. Body text is already sanitized by
    /// SafetyCopyPolicy inside the composer.
    private func narrativeCard(snapshot: InsightSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("What we're seeing")
                .font(.headline)

            ForEach(snapshot.narrativeCards) { narrative in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: narrativeIcon(for: narrative.id))
                            .foregroundStyle(narrativeColor(for: narrative.id))
                        Text(narrative.title)
                            .font(.subheadline.weight(.semibold))
                    }
                    Text(narrative.body)
                        .font(.subheadline)
                    HStack(spacing: 12) {
                        Text(confidenceLabel(narrative.confidence))
                            .font(.caption.weight(.bold))
                            .foregroundStyle(MoodboundDesign.tint)
                        Text(narrative.evidenceWindow)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if narrative.id != snapshot.narrativeCards.last?.id {
                    Divider()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .moodCard()
        .accessibilityIdentifier("insights-narrative-card")
    }

    private func narrativeIcon(for id: String) -> String {
        switch id {
        case "safety": return "shield.lefthalf.filled"
        case "trigger": return "bolt.heart"
        case "directional": return "arrow.left.arrow.right"
        case "phenotype": return "waveform.path.ecg"
        default: return "sparkles"
        }
    }

    private func narrativeColor(for id: String) -> Color {
        switch id {
        case "safety": return MoodboundDesign.accent
        case "trigger": return .pink
        case "directional": return .teal
        case "phenotype": return .indigo
        default: return MoodboundDesign.tint
        }
    }

    private func concernLabel(_ risk: Double) -> String {
        let pct = Int((risk * 100).rounded())
        if pct < 20 { return "Low (\(pct)%)" }
        if pct < 50 { return "Moderate (\(pct)%)" }
        return "High (\(pct)%)"
    }

    private func weatherEffectLabel(_ type: String, delta: Double) -> String {
        let abs = abs(delta)
        let direction = delta > 0 ? "lifts" : "lowers"
        if abs < 0.2 { return "\(type): No clear effect" }
        if abs < 0.5 { return "\(type) slightly \(direction) your mood" }
        return "\(type) noticeably \(direction) your mood"
    }

    private var appNow: Date {
        overrideTimestamp > 0 ? Date(timeIntervalSince1970: overrideTimestamp) : Date()
    }

    private func instabilityIndex(snapshot: InsightSnapshot) -> Double {
        let boundedDrift = min(1.0, snapshot.wassersteinDriftScore / 0.6)
        let boundedCI = min(1.0, snapshot.conformalCIWidth / 4.0)
        return (snapshot.bayesianChangeProbability * 0.5) + (boundedDrift * 0.3) + (boundedCI * 0.2)
    }

    private func outlookScore(snapshot: InsightSnapshot) -> Double {
        let instability = instabilityIndex(snapshot: snapshot) * 60
        let safety = snapshot.safety.posteriorRisk * 40
        let score = instability + safety
        return max(0, min(100, score))
    }

    private func scoreTrend(snapshot: InsightSnapshot) -> String {
        if snapshot.evidenceLevel == .insufficient { return "Gathering trend" }
        guard let avg7 = snapshot.avg7, let avg30 = snapshot.avg30 else { return "Gathering trend" }
        let delta = avg7 - avg30
        if delta > 0.6 { return "Rising" }
        if delta < -0.6 { return "Falling" }
        return "Stable"
    }

    private func outlookSummary(snapshot: InsightSnapshot, score: Double) -> String {
        if snapshot.evidenceLevel == .insufficient {
            return L10n.tr("outlook.summary.learning")
        }
        // Thresholds intentionally aligned with outlookBand so a single score
        // can't be labeled "Rough patch" by the badge while the supporting
        // summary line says it's only "bumpy".
        if score >= 75 {
            return L10n.tr("outlook.summary.rough")
        }
        if score >= 45 {
            return L10n.tr("outlook.summary.bumpy")
        }
        if snapshot.lowSleepCount14d > 0 {
            return L10n.tr("outlook.summary.low_sleep_watch")
        }
        return L10n.tr("outlook.summary.steady")
    }

    private func outcomeMeter(score: Double, color: Color) -> some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.secondary.opacity(0.16))
                    .frame(height: 10)

                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [color.opacity(0.7), color],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: max(10, proxy.size.width * (score / 100)), height: 10)
            }
        }
        .frame(height: 10)
    }

    private func phasePill(title: String, color: Color) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(color.opacity(0.14))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }

    private func outlookBand(for score: Double, evidenceLevel: EvidenceLevel) -> (label: String, color: Color) {
        if evidenceLevel == .insufficient { return ("Learning", .gray) }
        if score >= 75 { return ("Rough patch", .red) }
        if score >= 45 { return ("A bit bumpy", .orange) }
        return ("Smooth sailing", .green)
    }

    private func stabilityLabel(score: Double, evidenceLevel: EvidenceLevel) -> String {
        if evidenceLevel == .insufficient { return "Still getting to know your patterns" }
        if score >= 75 { return "Pretty turbulent right now" }
        if score >= 45 { return "Some choppiness" }
        if score >= 20 { return "Mostly calm" }
        return "Nice and steady"
    }

    private func currentPhase(snapshot: InsightSnapshot) -> (title: String, description: String, color: Color) {
        let anchor = snapshot.avg7 ?? snapshot.avg30 ?? 0
        let sleepIrregularity = snapshot.lowSleepCount14d + snapshot.highSleepCount14d

        if abs(anchor) < 0.5 {
            if sleepIrregularity >= 4 {
                return (
                    "Mixed",
                    "Your mood seems okay on average, but your sleep hasn't been very consistent.",
                    .purple
                )
            }
            return (
                "Balanced",
                "You're in a pretty even place right now. Nice and steady.",
                .green
            )
        }

        if anchor >= 0.5 {
            return (
                "Elevated",
                "Things are trending up. Keep an eye on your sleep and any impulsive urges.",
                .orange
            )
        }

        return (
            "Low",
            "Things are trending down. Protect your routine, lean on your people, and get rest.",
            .blue
        )
    }
}
