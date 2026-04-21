import SwiftUI
import SwiftData
import Charts

struct HistoryView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.modelContext) private var context
    @Query(sort: \MoodEntry.timestamp, order: .reverse) private var entries: [MoodEntry]
    @State private var timeRange: TimeRange = .week
    @State private var editingEntry: MoodEntry?
    @State private var selectedMoodDate: Date?
    @State private var selectedSleepDate: Date?
    @State private var showingDeleteError = false
    @State private var deleteErrorMessage = ""
    @AppStorage(AppClock.overrideTimestampKey) private var overrideTimestamp: Double = 0

    enum TimeRange: String, CaseIterable {
        case week = "7D"
        case month = "30D"
        case quarter = "90D"
    }

    private struct DailyAggregate: Identifiable {
        let date: Date
        let mood: Double
        // sleep is optional because sleepHours == 0 is the "unknown" sentinel,
        // and a day with no known sleep observation should not contribute to
        // averages or render a zero-height bar in the chart.
        let sleep: Double?
        var id: Date { date }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("History")
                            .font(.system(size: 48, weight: .black, design: .rounded))
                            .foregroundStyle(.primary)
                        rangeControl
                    }

                    if aggregatedEntries.isEmpty {
                        ContentUnavailableView(
                            "No entries yet",
                            systemImage: "chart.xyaxis.line",
                            description: Text("Start logging to see your trends")
                        )
                        .frame(height: 300)
                        .historyCard()
                    } else {
                        windowSummaryCard
                        if let snapshot = insightSnapshot {
                            forecastOutlookCard(snapshot: snapshot)
                        }
                        chartLayout
                        recentEntriesSection
                    }
                }
                .padding(.horizontal, horizontalSizeClass == .regular ? 24 : 16)
                .padding(.vertical, 16)
                .frame(maxWidth: horizontalSizeClass == .regular ? 980 : .infinity)
                .frame(maxWidth: .infinity)
            }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(item: $editingEntry) { entry in
                NewEntryView(entryToEdit: entry)
            }
            .alert("Couldn't Delete Entry", isPresented: $showingDeleteError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(deleteErrorMessage)
            }
        }
    }

    private var rangeControl: some View {
        HStack(spacing: 6) {
            ForEach(TimeRange.allCases, id: \.self) { range in
                Button {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
                        timeRange = range
                    }
                } label: {
                    Text(range.rawValue)
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                        .foregroundStyle(timeRange == range ? Color.primary : Color.secondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(timeRange == range ? Color(.systemBackground) : Color.clear)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color(.systemGray5))
        )
    }

    private var recentEntriesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Recent Entries")
                .font(.system(size: 22, weight: .bold, design: .rounded))

            LazyVStack(spacing: 10) {
                ForEach(filteredEntries) { entry in
                    HStack(spacing: 10) {
                        MoodEntryRow(entry: entry)
                            .onTapGesture {
                                editingEntry = entry
                            }

                        Menu {
                            Button {
                                editingEntry = entry
                            } label: {
                                Label("Edit", systemImage: "pencil")
                            }
                            Button(role: .destructive) {
                                delete(entry)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        } label: {
                            Image(systemName: "ellipsis")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(.secondary)
                                .frame(width: 34, height: 34)
                                .background(Circle().fill(Color(.systemGray6)))
                        }
                        .menuStyle(.button)
                        .accessibilityLabel("Entry actions")
                        .accessibilityIdentifier("entry-actions-menu")
                    }
                    .contextMenu {
                        Button {
                            editingEntry = entry
                        } label: {
                            Label("Edit", systemImage: "pencil")
                        }
                        Button(role: .destructive) {
                            delete(entry)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var chartLayout: some View {
        if horizontalSizeClass == .regular {
            HStack(alignment: .top, spacing: 12) {
                moodChart
                sleepChart
            }
        } else {
            moodChart
            sleepChart
        }
    }

    private var windowSummaryCard: some View {
        let avgMood = aggregatedEntries.map(\.mood).average
        let moodVolatility = aggregatedEntries.map(\.mood).populationStdDev
        let knownSleep = aggregatedEntries.compactMap(\.sleep)
        let avgSleep: Double? = knownSleep.isEmpty ? nil : knownSleep.average

        return HStack {
            summaryMetric(
                title: "Avg Mood",
                value: String(format: "%+.1f", avgMood),
                tint: MoodboundDesign.tint
            )
            Spacer()
            summaryMetric(
                title: "Volatility",
                value: String(format: "%.2f", moodVolatility),
                tint: .orange
            )
            Spacer()
            summaryMetric(
                title: "Avg Sleep",
                value: avgSleep.map { String(format: "%.1fh", $0) } ?? "—",
                tint: .indigo
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .historyCard()
    }

    private func summaryMetric(title: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(tint)
        }
    }

    private var filteredEntries: [MoodEntry] {
        let days: Int
        switch timeRange {
        case .week:
            days = 7
        case .month:
            days = 30
        case .quarter:
            days = 90
        }
        // Anchor to startOfDay so entries from the morning of the boundary
        // day are included regardless of the current wall-clock time.
        let calendar = Calendar.current
        let startToday = calendar.startOfDay(for: appNow)
        let cutoff = calendar.date(byAdding: .day, value: -(days - 1), to: startToday) ?? startToday
        return entries.filter { $0.timestamp >= cutoff }
    }

    private var aggregatedEntries: [DailyAggregate] {
        let grouped = Dictionary(grouping: filteredEntries) { entry in
            Calendar.current.startOfDay(for: entry.timestamp)
        }

        return grouped.map { date, bucket in
            let moodAverage = bucket.reduce(0.0) { $0 + Double($1.moodLevel) } / Double(bucket.count)
            // sleepHours == 0 means "unknown" — a user logged everything except
            // their sleep that day. Average only over known values; if every
            // entry that day was unknown, the day has no sleep aggregate.
            let knownSleep = bucket.map(\.sleepHours).filter { $0 > 0 }
            let sleepAverage: Double? = knownSleep.isEmpty ? nil : knownSleep.reduce(0, +) / Double(knownSleep.count)
            return DailyAggregate(date: date, mood: moodAverage, sleep: sleepAverage)
        }
        .sorted { $0.date < $1.date }
    }

    private var moodChart: some View {
        let latentBackgrounds: [(date: Date, state: LatentMoodState)] = {
            guard let snapshot = insightSnapshot else { return [] }
            return latentStateBackgrounds(for: aggregatedEntries, posteriors: snapshot.latentPosteriors)
        }()
        let distinctStates: [LatentMoodState] = Array(Set(latentBackgrounds.map(\.state)))
            .sorted { Self.label(for: $0) < Self.label(for: $1) }

        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Mood Trend")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                Spacer()
                if !distinctStates.isEmpty {
                    HStack(spacing: 8) {
                        ForEach(distinctStates, id: \.self) { state in
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(Self.color(for: state).opacity(0.5))
                                    .frame(width: 8, height: 8)
                                Text(Self.label(for: state))
                                    .font(.caption2.weight(.medium))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            Chart {
                // B2: Per-day latent state backgrounds, rendered first so
                // they sit below the mood line/area. Each day gets a low-opacity
                // rectangle across the full y-range tinted by its dominant
                // latent state. Uses RectangleMark with explicit date bounds
                // so SwiftUI Charts renders a hard per-day band without
                // interpolation.
                ForEach(latentBackgrounds, id: \.date) { bg in
                    let end = Calendar.current.date(byAdding: .day, value: 1, to: bg.date) ?? bg.date
                    RectangleMark(
                        xStart: .value("Day Start", bg.date),
                        xEnd: .value("Day End", end),
                        yStart: .value("Floor", -3),
                        yEnd: .value("Ceiling", 3)
                    )
                    .foregroundStyle(Self.color(for: bg.state).opacity(0.12))
                }

                ForEach(aggregatedEntries) { point in
                    AreaMark(
                        x: .value("Date", point.date),
                        y: .value("Mood", point.mood)
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [MoodboundDesign.tint.opacity(0.28), MoodboundDesign.tint.opacity(0.02)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                    LineMark(
                        x: .value("Date", point.date),
                        y: .value("Mood", point.mood)
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(MoodboundDesign.tint)
                    .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))

                    PointMark(
                        x: .value("Date", point.date),
                        y: .value("Mood", point.mood)
                    )
                    .foregroundStyle(MoodboundDesign.tint.opacity(0.9))
                    .symbolSize(30)
                }

                RuleMark(y: .value("Baseline", 0))
                    .foregroundStyle(.green.opacity(0.42))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))

                if let selected = selectedMoodPoint {
                    RuleMark(x: .value("Selected Date", selected.date))
                        .foregroundStyle(MoodboundDesign.tint.opacity(0.5))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))

                    PointMark(
                        x: .value("Selected Date", selected.date),
                        y: .value("Selected Mood", selected.mood)
                    )
                    .symbolSize(96)
                    .foregroundStyle(MoodboundDesign.accent.opacity(0.9))
                }
            }
            .chartYScale(domain: -3...3)
            .chartXSelection(value: $selectedMoodDate)
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.6, dash: [3, 3]))
                        .foregroundStyle(Color(.systemGray4))
                    AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .chartYAxis {
                AxisMarks(values: [-3, -2, 0, 1, 3]) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.6))
                        .foregroundStyle(Color(.systemGray4))
                    AxisValueLabel {
                        if let v = value.as(Int.self) {
                            Text(MoodScale(rawValue: v)?.shortLabel ?? "")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .chartPlotStyle { plot in
                plot.background(Color(.systemGray6).opacity(0.35))
            }
            .frame(height: horizontalSizeClass == .regular ? 270 : 250)

            if let selectedEntry = selectedMoodEntry {
                Text("\(selectedEntry.moodEmoji) \(selectedEntry.moodLabel) at \(selectedEntry.timestamp.formatted(date: .abbreviated, time: .shortened))")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .historyCard()
    }

    private var sleepChart: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Sleep Pattern")
                .font(.system(size: 22, weight: .bold, design: .rounded))

            Chart {
                ForEach(aggregatedEntries) { point in
                    if let sleep = point.sleep {
                        BarMark(
                            x: .value("Date", point.date, unit: .day),
                            y: .value("Hours", sleep)
                        )
                        .foregroundStyle(
                            sleep < 6 || sleep > 10
                            ? MoodboundDesign.accent.opacity(0.68)
                            : MoodboundDesign.tint.opacity(0.72)
                        )
                        .cornerRadius(4)
                    }
                }

                RuleMark(y: .value("Target", 8))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .foregroundStyle(.green.opacity(0.4))

                if let selected = selectedSleepPoint {
                    RuleMark(x: .value("Selected Date", selected.date, unit: .day))
                        .foregroundStyle(MoodboundDesign.tint.opacity(0.5))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                }
            }
            .chartYScale(domain: 0...16)
            .chartXSelection(value: $selectedSleepDate)
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.6, dash: [3, 3]))
                        .foregroundStyle(Color(.systemGray4))
                    AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { _ in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.6))
                        .foregroundStyle(Color(.systemGray4))
                    AxisValueLabel()
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .chartPlotStyle { plot in
                plot.background(Color(.systemGray6).opacity(0.35))
            }
            .frame(height: horizontalSizeClass == .regular ? 270 : 250)

            if let selectedEntry = selectedSleepEntry {
                // sleepHours == 0 is the "unknown" sentinel; the chart hides
                // those bars, so the popover should say "unlogged" instead of
                // printing a phantom 0.0h value.
                let label: String = selectedEntry.sleepHours > 0
                    ? "\(String(format: "%.1f", selectedEntry.sleepHours))h sleep on \(selectedEntry.timestamp.formatted(date: .abbreviated, time: .omitted))"
                    : "Sleep not logged on \(selectedEntry.timestamp.formatted(date: .abbreviated, time: .omitted))"
                Text(label)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .historyCard()
    }

    private var appNow: Date {
        overrideTimestamp > 0 ? Date(timeIntervalSince1970: overrideTimestamp) : Date()
    }

    // MARK: - Insight snapshot (B1 + B2)

    private var insightSnapshot: InsightSnapshot? {
        guard entries.count >= 3 else { return nil }
        return InsightEngine.snapshot(entries: entries, now: appNow)
    }

    /// Maps each aggregated day to the dominant latent state, using the
    /// nearest-by-timestamp posterior. Used as a background overlay under
    /// the mood chart (B2) so users can see where they were (down/steady/
    /// elevated/unstable) in addition to raw mood.
    private func latentStateBackgrounds(
        for points: [DailyAggregate],
        posteriors: [LatentStateDayPosterior]
    ) -> [(date: Date, state: LatentMoodState)] {
        guard !posteriors.isEmpty else { return [] }
        let calendar = Calendar.current
        // Build a lookup from startOfDay → dominant state, picking the
        // latest posterior for that day if multiple exist.
        var byDay: [Date: LatentStateDayPosterior] = [:]
        for posterior in posteriors {
            let day = calendar.startOfDay(for: posterior.timestamp)
            if let existing = byDay[day], existing.timestamp >= posterior.timestamp {
                continue
            }
            byDay[day] = posterior
        }
        return points.compactMap { point in
            let day = calendar.startOfDay(for: point.date)
            guard let posterior = byDay[day] else { return nil }
            return (day, posterior.distribution.dominantState)
        }
    }

    private static func color(for state: LatentMoodState) -> Color {
        switch state {
        case .depressive: return .blue
        case .stable: return .green
        case .elevated: return .orange
        case .unstable: return .purple
        }
    }

    private static func label(for state: LatentMoodState) -> String {
        switch state {
        case .depressive: return "Low"
        case .stable: return "Steady"
        case .elevated: return "Elevated"
        case .unstable: return "Unstable"
        }
    }

    // MARK: - Forecast outlook card (B1)

    /// Renders the 7-day risk forecast point estimate and its conformalized
    /// confidence interval as a dedicated card. Kept separate from the mood
    /// chart because the forecast lives in [0,1] risk space, not [-3,3] mood
    /// space — overlaying them on the same axis would be misleading.
    private func forecastOutlookCard(snapshot: InsightSnapshot) -> some View {
        let pointPct = Int((snapshot.forecastValue * 100).rounded())
        let lowPct = Int((snapshot.forecastCILow * 100).rounded())
        let highPct = Int((snapshot.forecastCIHigh * 100).rounded())
        let widthPct = max(0, highPct - lowPct)

        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("7-Day Outlook")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                Spacer()
                Text("\(pointPct)%")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(MoodboundDesign.accent)
            }

            Text("Estimated chance of an episode-level shift in the next 7 days, with a confidence range based on how much data we have to work with.")
                .font(.caption)
                .foregroundStyle(.secondary)

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color(.systemGray5))
                        .frame(height: 12)
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [
                                    MoodboundDesign.accent.opacity(0.35),
                                    MoodboundDesign.accent.opacity(0.75),
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(
                            width: max(8, proxy.size.width * CGFloat(widthPct) / 100),
                            height: 12
                        )
                        .offset(x: proxy.size.width * CGFloat(lowPct) / 100)
                    Circle()
                        .fill(MoodboundDesign.accent)
                        .frame(width: 14, height: 14)
                        .offset(x: proxy.size.width * CGFloat(pointPct) / 100 - 7)
                }
            }
            .frame(height: 16)

            HStack {
                Text("Low: \(lowPct)%")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("High: \(highPct)%")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .historyCard()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "Seven-day outlook: \(pointPct) percent, range \(lowPct) to \(highPct) percent"
        )
    }

    private var selectedMoodEntry: MoodEntry? {
        guard let date = selectedMoodDate else { return nil }
        return HistorySelectionService.nearestEntry(to: date, entries: filteredEntries)
    }

    private var selectedSleepEntry: MoodEntry? {
        guard let date = selectedSleepDate else { return nil }
        return HistorySelectionService.nearestEntry(to: date, entries: filteredEntries)
    }

    private var selectedMoodPoint: DailyAggregate? {
        guard let date = selectedMoodDate else { return nil }
        return nearestAggregate(to: date, in: aggregatedEntries)
    }

    private var selectedSleepPoint: DailyAggregate? {
        guard let date = selectedSleepDate else { return nil }
        return nearestAggregate(to: date, in: aggregatedEntries)
    }

    private func nearestAggregate(to date: Date, in points: [DailyAggregate]) -> DailyAggregate? {
        points.min { lhs, rhs in
            abs(lhs.date.timeIntervalSince(date)) < abs(rhs.date.timeIntervalSince(date))
        }
    }

    private func delete(_ entry: MoodEntry) {
        do {
            context.delete(entry)
            try context.save()
        } catch {
            AppLogger.error("Failed to delete mood entry", error: error)
            deleteErrorMessage = error.localizedDescription
            showingDeleteError = true
        }
    }
}

private struct HistoryCardModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color(.separator).opacity(0.3), lineWidth: colorScheme == .dark ? 0.5 : 1)
            )
            .shadow(color: Color.black.opacity(colorScheme == .dark ? 0 : 0.03), radius: 8, y: 3)
    }
}

private extension View {
    func historyCard() -> some View {
        modifier(HistoryCardModifier())
    }
}

private extension Array where Element == Double {
    var average: Double {
        guard !isEmpty else { return 0 }
        return reduce(0, +) / Double(count)
    }

    var populationStdDev: Double {
        guard !isEmpty else { return 0 }
        let mean = average
        let variance = map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(count)
        return sqrt(variance)
    }
}
