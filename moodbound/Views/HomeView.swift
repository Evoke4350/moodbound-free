import SwiftUI
import SwiftData

struct HomeView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Query(sort: \MoodEntry.timestamp, order: .reverse) private var entries: [MoodEntry]
    @State private var showingNewEntry = false
    @State private var showingSettings = false
    @State private var showingSafetyPlan = false
    @State private var viewModel = MoodViewModel()
    @AppStorage(AppClock.overrideTimestampKey) private var overrideTimestamp: Double = 0

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    greetingCard
                    if let snapshot = insightSnapshot {
                        todayOutlookCard(snapshot: snapshot)
                    }
                    quickAction
                    statsGrid
                    recentSection
                }
                .padding(.horizontal, horizontalSizeClass == .regular ? 24 : 16)
                .padding(.vertical, 16)
                .frame(maxWidth: horizontalSizeClass == .regular ? 960 : .infinity)
                .frame(maxWidth: .infinity)
            }
            .navigationTitle("Today")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showingSafetyPlan = true
                    } label: {
                        Image(systemName: "cross.case.fill")
                            .foregroundStyle(.red.opacity(0.85))
                    }
                    .accessibilityLabel("Safety Plan")
                    .accessibilityIdentifier("safety-plan-button")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityIdentifier("settings-button")
                }
            }
            .sheet(isPresented: $showingNewEntry) {
                NewEntryView()
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView()
            }
            .sheet(isPresented: $showingSafetyPlan) {
                SafetyPlanView()
            }
        }
        .animation(.smooth(duration: 0.28), value: entries.count)
    }

    private var greetingCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(greeting)
                .font(.title3.weight(.semibold))

            if let latest = entries.first {
                HStack(alignment: .firstTextBaseline) {
                    Text(latest.moodEmoji)
                        .font(.largeTitle)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(latest.moodLabel)
                            .font(.title2.weight(.bold))
                        Text(latest.timestamp, format: .dateTime.weekday(.wide).month().day().hour().minute())
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                Text("No entries yet. Start with your first check-in.")
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                if let streak = streakText {
                    badge(text: streak, systemName: "flame.fill", tint: .orange)
                }
                if overrideTimestamp > 0 {
                    badge(text: "Time travel active", systemName: "clock.arrow.circlepath", tint: MoodboundDesign.accent)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .moodCard()
    }

    private var quickAction: some View {
        Button {
            showingNewEntry = true
        } label: {
            HStack {
                Image(systemName: viewModel.hasLoggedToday(entries: entries, now: appNow) ? "pencil.circle.fill" : "plus.circle.fill")
                    .font(.title2)
                Text(viewModel.hasLoggedToday(entries: entries, now: appNow) ? "Log Another Entry" : "Log Today's Mood")
                    .fontWeight(.semibold)
                Spacer()
                Image(systemName: "arrow.right")
                    .font(.footnote.weight(.bold))
            }
            .padding(.vertical, 8)
        }
        .buttonStyle(.borderedProminent)
        .buttonStyle(PressableScaleButtonStyle())
        .tint(MoodboundDesign.tint)
        .accessibilityIdentifier("log-entry-button")
    }

    private func todayOutlookCard(snapshot: InsightSnapshot) -> some View {
        let score = outlookScore(snapshot: snapshot)
        let band = outlookBand(score: score)
        let trend = outlookTrend(snapshot: snapshot)

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("How's It Looking")
                    .font(.headline)
                Spacer()
                Text(band.label)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(band.color.opacity(0.14))
                    .foregroundStyle(band.color)
                    .clipShape(Capsule())
            }

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(stabilityLabel(score: score))
                    .font(.title3.weight(.bold))
                Spacer()
                Text(trend)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            Text(outlookSummary(snapshot: snapshot, score: score))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .moodCard()
    }

    private var statsGrid: some View {
        let columns = horizontalSizeClass == .regular
            ? [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]
            : [GridItem(.flexible()), GridItem(.flexible())]

        return LazyVGrid(columns: columns, spacing: 10) {
            statTile(
                title: "Entries (7d)",
                value: "\(entriesInLastDays(7))",
                icon: "calendar.badge.clock",
                tint: .blue
            )
            statTile(
                title: "Avg Mood (7d)",
                value: weekAverageText,
                icon: "waveform.path.ecg",
                tint: MoodboundDesign.tint
            )
            statTile(
                title: "Avg Sleep (7d)",
                value: weekSleepText,
                icon: "moon.stars.fill",
                tint: .indigo
            )
        }
    }

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Recent")
                .font(.headline)
                .foregroundStyle(.secondary)

            if entries.isEmpty {
                Text("Your entries will appear here.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .moodCard()
            } else {
                ForEach(entries.prefix(6)) { entry in
                    MoodEntryRow(entry: entry)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
        }
    }

    private func statTile(title: String, value: String, icon: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.weight(.bold))
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .moodCard()
    }

    private func badge(text: String, systemName: String, tint: Color) -> some View {
        Label(text, systemImage: systemName)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(tint.opacity(0.15))
            .foregroundStyle(tint)
            .clipShape(Capsule())
            .transition(.scale.combined(with: .opacity))
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: appNow)
        switch hour {
        case 5..<12: return "Good morning"
        case 12..<17: return "Good afternoon"
        case 17..<21: return "Good evening"
        default: return "Hey there"
        }
    }

    private var streakText: String? {
        let streak = viewModel.streakDays(entries: entries, now: appNow)
        if streak > 1 {
            return "\(streak)-day streak"
        }
        return nil
    }

    private var weekAverageText: String {
        guard let average = viewModel.averageMood(entries: entries, days: 7, now: appNow) else { return "No data" }
        return String(format: "%+.1f", average)
    }

    private var weekSleepText: String {
        let cutoff = Calendar.current.date(byAdding: .day, value: -7, to: appNow) ?? appNow
        let recent = entries.filter { $0.timestamp >= cutoff }
        guard !recent.isEmpty else { return "No data" }
        let avg = recent.reduce(0.0) { $0 + $1.sleepHours } / Double(recent.count)
        return String(format: "%.1f h", avg)
    }

    private func entriesInLastDays(_ days: Int) -> Int {
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: appNow) ?? appNow
        return entries.filter { $0.timestamp >= cutoff }.count
    }

    private var insightSnapshot: InsightSnapshot? {
        guard entries.count >= 3 else { return nil }
        return InsightEngine.snapshot(entries: entries, now: appNow)
    }

    private func outlookScore(snapshot: InsightSnapshot) -> Double {
        let drift = min(1.0, snapshot.wassersteinDriftScore / 0.6)
        let uncertainty = min(1.0, snapshot.conformalCIWidth / 4.0)
        let instability = (snapshot.bayesianChangeProbability * 0.5) + (drift * 0.3) + (uncertainty * 0.2)
        return max(0, min(100, (instability * 60) + (snapshot.safety.posteriorRisk * 40)))
    }

    private func outlookTrend(snapshot: InsightSnapshot) -> String {
        guard let avg7 = snapshot.avg7, let avg30 = snapshot.avg30 else { return "Gathering trend" }
        let delta = avg7 - avg30
        if delta > 0.6 { return "Rising" }
        if delta < -0.6 { return "Falling" }
        return "Stable"
    }

    private func outlookBand(score: Double) -> (label: String, color: Color) {
        if score >= 75 { return ("Rough patch", .red) }
        if score >= 45 { return ("A bit bumpy", .orange) }
        return ("Smooth sailing", .green)
    }

    private func stabilityLabel(score: Double) -> String {
        if score >= 75 { return "Pretty turbulent right now" }
        if score >= 45 { return "Some choppiness" }
        if score >= 20 { return "Mostly calm" }
        return "Nice and steady"
    }

    private func outlookSummary(snapshot: InsightSnapshot, score: Double) -> String {
        if score >= 70 {
            return L10n.tr("outlook.summary.rough")
        }
        if score >= 40 {
            return L10n.tr("outlook.summary.bumpy")
        }
        if snapshot.lowSleepCount14d > 0 {
            return L10n.tr("outlook.summary.low_sleep_watch")
        }
        return L10n.tr("outlook.summary.steady")
    }

    private var appNow: Date {
        overrideTimestamp > 0 ? Date(timeIntervalSince1970: overrideTimestamp) : Date()
    }
}

struct MoodEntryRow: View {
    let entry: MoodEntry

    var body: some View {
        HStack(spacing: 12) {
            Text(entry.moodEmoji)
                .font(.title2)

            VStack(alignment: .leading, spacing: 4) {
                Text(entry.moodLabel)
                    .font(.headline)
                Text(entry.timestamp, format: .dateTime.month().day().hour().minute())
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Label("\(entry.energy)", systemImage: "bolt.fill")
                    .font(.subheadline)
                    .foregroundStyle(.orange)
                Label(String(format: "%.1fh", entry.sleepHours), systemImage: "moon.fill")
                    .font(.subheadline)
                    .foregroundStyle(.indigo)
                if let weather = entry.weatherSummary, let weatherEmoji = entry.weatherEmoji {
                    Text("\(weatherEmoji) \(weather)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .moodCard()
    }
}
