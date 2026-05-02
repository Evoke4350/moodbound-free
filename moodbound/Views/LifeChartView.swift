import SwiftUI
import SwiftData

/// NIMH Life Chart Method (LCM) visualization. Bars rise above the
/// zero line for activation, drop below for depression, with height
/// proportional to severity band. Annotations (medication changes,
/// high-intensity triggers) sit on the zero line. Tap a bar to see
/// that day's entries.
struct LifeChartView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Query(sort: \MoodEntry.timestamp, order: .reverse) private var entries: [MoodEntry]
    @AppStorage(AppClock.overrideTimestampKey) private var overrideTimestamp: Double = 0

    @State private var window: LifeChartWindow = .days(90)
    @State private var selectedDay: Date?

    private static let chartHeight: CGFloat = 200
    private static let zeroLineThickness: CGFloat = 1
    private static let annotationGlyphSize: CGFloat = 14

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    windowPicker
                    if entries.count < 7 {
                        emptyState
                    } else {
                        chartCard
                        legendCard
                    }
                }
                .padding(16)
            }
            .navigationTitle("Life chart")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(item: selectedDayBinding) { selection in
                DayDetailSheet(day: selection.day, entries: selection.entries)
                    .presentationDetents([.medium, .large])
            }
        }
    }

    private var windowPicker: some View {
        Picker("Window", selection: $window) {
            Text("30d").tag(LifeChartWindow.days(30))
            Text("90d").tag(LifeChartWindow.days(90))
            Text("1y").tag(LifeChartWindow.days(365))
            Text("All").tag(LifeChartWindow.all)
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier("life-chart-window-picker")
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Need at least 7 days of entries", systemImage: "chart.bar.xaxis")
                .font(.headline)
            Text("Log a week's worth of check-ins and your life chart appears here.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .moodCard()
    }

    private var chartCard: some View {
        let data = LifeChartService.build(entries: entries, window: window, now: appNow)
        let totalDays = data.bars.count
        let barWidth: CGFloat = max(2, min(12, 720 / CGFloat(max(1, totalDays))))
        let chartWidth = barWidth * CGFloat(totalDays)
        let containerWidth: CGFloat = max(chartWidth, 320)

        return VStack(alignment: .leading, spacing: 8) {
            Text(windowLabel(data: data))
                .font(.caption)
                .foregroundStyle(.secondary)

            ScrollView(.horizontal, showsIndicators: false) {
                ZStack(alignment: .topLeading) {
                    chartCanvas(data: data, barWidth: barWidth, width: containerWidth)
                    annotationsOverlay(data: data, barWidth: barWidth, width: containerWidth)
                }
                .frame(width: containerWidth, height: Self.chartHeight)
                .contentShape(Rectangle())
                .gesture(tapGesture(data: data, barWidth: barWidth))
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(accessibilityLabel(data: data))
        }
        .moodCard()
    }

    private func chartCanvas(data: LifeChartData, barWidth: CGFloat, width: CGFloat) -> some View {
        Canvas { context, size in
            let zeroY = size.height / 2
            // Zero baseline.
            let zeroPath = Path { p in
                p.move(to: CGPoint(x: 0, y: zeroY))
                p.addLine(to: CGPoint(x: size.width, y: zeroY))
            }
            context.stroke(zeroPath, with: .color(.secondary.opacity(0.4)), lineWidth: Self.zeroLineThickness)

            for (index, bar) in data.bars.enumerated() {
                let x = CGFloat(index) * barWidth
                guard let band = bar.band else {
                    // Empty day: faint baseline tick.
                    let tickPath = Path { p in
                        p.move(to: CGPoint(x: x + barWidth / 2, y: zeroY - 2))
                        p.addLine(to: CGPoint(x: x + barWidth / 2, y: zeroY + 2))
                    }
                    context.stroke(tickPath, with: .color(.secondary.opacity(0.25)), lineWidth: 1)
                    continue
                }

                let weight = band.barWeight
                let halfHeight = (size.height / 2) - 8
                let barHeight = halfHeight * weight
                let rect: CGRect
                switch band.pole {
                case .elevation:
                    rect = CGRect(x: x + 1, y: zeroY - barHeight, width: barWidth - 2, height: barHeight)
                case .depression:
                    rect = CGRect(x: x + 1, y: zeroY, width: barWidth - 2, height: barHeight)
                case .euthymic:
                    let dotPath = Path(ellipseIn: CGRect(x: x + barWidth / 2 - 2, y: zeroY - 2, width: 4, height: 4))
                    context.fill(dotPath, with: .color(.green.opacity(0.7)))
                    continue
                }
                let path = Path(roundedRect: rect, cornerRadius: barWidth >= 6 ? 2 : 1)
                context.fill(path, with: .color(color(for: band)))
            }
        }
        .frame(width: width, height: Self.chartHeight)
    }

    private func annotationsOverlay(data: LifeChartData, barWidth: CGFloat, width: CGFloat) -> some View {
        Canvas { context, size in
            let zeroY = size.height / 2
            // Map day → bar index for annotation placement.
            let indexByDay = Dictionary(uniqueKeysWithValues: data.bars.enumerated().map { ($0.element.day, $0.offset) })

            for annotation in data.annotations {
                guard let index = indexByDay[annotation.day] else { continue }
                let centerX = CGFloat(index) * barWidth + barWidth / 2
                let glyphRect = CGRect(
                    x: centerX - Self.annotationGlyphSize / 2,
                    y: zeroY - Self.annotationGlyphSize / 2,
                    width: Self.annotationGlyphSize,
                    height: Self.annotationGlyphSize
                )
                switch annotation {
                case .medicationStarted, .medicationStopped:
                    context.fill(Path(ellipseIn: glyphRect), with: .color(.mint.opacity(0.85)))
                case .highIntensityTrigger:
                    context.fill(
                        Path { p in
                            p.move(to: CGPoint(x: centerX, y: zeroY - Self.annotationGlyphSize / 2))
                            p.addLine(to: CGPoint(x: centerX + Self.annotationGlyphSize / 2, y: zeroY + Self.annotationGlyphSize / 2))
                            p.addLine(to: CGPoint(x: centerX - Self.annotationGlyphSize / 2, y: zeroY + Self.annotationGlyphSize / 2))
                            p.closeSubpath()
                        },
                        with: .color(.pink.opacity(0.85))
                    )
                }
            }

            // Mixed-features marker: small purple chevron just above zero.
            for (index, bar) in data.bars.enumerated() where bar.isMixedFeatures {
                let centerX = CGFloat(index) * barWidth + barWidth / 2
                let chevron = Path { p in
                    p.move(to: CGPoint(x: centerX - 3, y: zeroY - 8))
                    p.addLine(to: CGPoint(x: centerX, y: zeroY - 4))
                    p.addLine(to: CGPoint(x: centerX + 3, y: zeroY - 8))
                }
                context.stroke(chevron, with: .color(.purple), lineWidth: 1.5)
            }
        }
        .frame(width: width, height: Self.chartHeight)
        .allowsHitTesting(false)
    }

    private func tapGesture(data: LifeChartData, barWidth: CGFloat) -> some Gesture {
        SpatialTapGesture()
            .onEnded { value in
                let index = Int(value.location.x / barWidth)
                guard index >= 0, index < data.bars.count else { return }
                let bar = data.bars[index]
                guard bar.entryCount > 0 else { return }
                let dayEntries = entriesOnDay(bar.day)
                selectedDay = bar.day
                pendingSelection = DaySelection(day: bar.day, entries: dayEntries)
            }
    }

    @State private var pendingSelection: DaySelection?

    private var selectedDayBinding: Binding<DaySelection?> {
        Binding(
            get: { pendingSelection },
            set: { newValue in
                pendingSelection = newValue
                if newValue == nil { selectedDay = nil }
            }
        )
    }

    private func entriesOnDay(_ day: Date) -> [MoodEntry] {
        let calendar = Calendar.current
        return entries
            .filter { calendar.isDate($0.timestamp, inSameDayAs: day) }
            .sorted { $0.timestamp < $1.timestamp }
    }

    private var legendCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Reading the chart")
                .font(.headline)
            legendRow(color: .red, label: "Bars above the line: activation / mania")
            legendRow(color: .blue, label: "Bars below the line: depression")
            legendRow(color: .mint, label: "Circle: medication change")
            legendRow(color: .pink, label: "Triangle: high-intensity trigger")
            legendRow(color: .purple, label: "Chevron: mixed-features day")
            Text("Severity bands follow the NIMH Life Chart Method, collapsed to fit Moodbound's 3-level mood scale per pole.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .moodCard()
    }

    private func legendRow(color: Color, label: String) -> some View {
        HStack(spacing: 8) {
            Circle().fill(color).frame(width: 10, height: 10)
            Text(label).font(.caption)
        }
    }

    private func color(for band: LifeChartBand) -> Color {
        switch band {
        case .severeDepression: return .indigo
        case .moderateHighDepression: return .blue
        case .moderateLowDepression: return .cyan
        case .euthymic: return .green
        case .moderateLowElevation: return .yellow
        case .moderateHighElevation: return .orange
        case .severeMania: return .red
        }
    }

    private func windowLabel(data: LifeChartData) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        let lastVisible = data.bars.last?.day ?? data.window.start
        return "\(formatter.string(from: data.window.start)) → \(formatter.string(from: lastVisible))"
    }

    private func accessibilityLabel(data: LifeChartData) -> String {
        let logged = data.bars.filter { $0.band != nil }.count
        let mixedDays = data.bars.filter { $0.isMixedFeatures }.count
        return "Life chart, \(data.bars.count) days, \(logged) logged, \(mixedDays) mixed-feature days, \(data.annotations.count) annotations"
    }

    private var appNow: Date {
        overrideTimestamp > 0 ? Date(timeIntervalSince1970: overrideTimestamp) : AppClock.now
    }
}

private struct DaySelection: Identifiable, Equatable {
    let day: Date
    let entries: [MoodEntry]
    var id: Date { day }

    static func == (lhs: DaySelection, rhs: DaySelection) -> Bool {
        lhs.day == rhs.day && lhs.entries.map(\.persistentModelID) == rhs.entries.map(\.persistentModelID)
    }
}

private struct DayDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    let day: Date
    let entries: [MoodEntry]

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(entries) { entry in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(entry.moodEmoji).font(.title3)
                                Text(entry.moodLabel).font(.headline)
                                Spacer()
                                Text(entry.timestamp, format: .dateTime.hour().minute())
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            HStack(spacing: 12) {
                                Label("\(entry.energy)", systemImage: "bolt.fill").foregroundStyle(.orange)
                                Label(String(format: "%.1fh", entry.sleepHours), systemImage: "moon.fill").foregroundStyle(.indigo)
                            }
                            .font(.caption)
                            if !entry.note.isEmpty {
                                Text(entry.note).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                } header: {
                    Text(day, format: .dateTime.weekday(.wide).month().day().year())
                }
            }
            .navigationTitle("Day detail")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
