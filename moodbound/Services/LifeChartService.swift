import Foundation

/// Window sizes shown in the chart's segmented control.
enum LifeChartWindow: Hashable {
    case days(Int)
    case all

    var label: String {
        switch self {
        case .days(30): return "30d"
        case .days(90): return "90d"
        case .days(365): return "1y"
        case .days(let n): return "\(n)d"
        case .all: return "All"
        }
    }
}

struct LifeChartData: Equatable {
    let bars: [LifeChartDayBar]
    let annotations: [LifeChartAnnotation]
    let window: DateInterval
}

/// Composes a `LifeChartDayReducer` and a list of
/// `LifeChartAnnotationProvider`s into a single chart payload. Both
/// strategy slots default to the v1 production picks; tests inject
/// their own to exercise edge cases without faking entries.
enum LifeChartService {
    static let defaultReducer: LifeChartDayReducer = WorstOfDayReducer()
    static let defaultAnnotationProviders: [LifeChartAnnotationProvider] = [
        MedicationChangeProvider(),
        HighIntensityTriggerProvider(),
    ]

    static func build(
        entries: [MoodEntry],
        window: LifeChartWindow,
        now: Date = AppClock.now,
        calendar: Calendar = .current,
        reducer: LifeChartDayReducer = defaultReducer,
        annotationProviders: [LifeChartAnnotationProvider] = defaultAnnotationProviders
    ) -> LifeChartData {
        let interval = resolveInterval(
            window: window,
            entries: entries,
            now: now,
            calendar: calendar
        )

        let inWindow = entries.filter { interval.contains($0.timestamp) }
        let entriesByDay = Dictionary(grouping: inWindow) {
            calendar.startOfDay(for: $0.timestamp)
        }
        let mixedDays = InsightEngine.mixedFeatureDays(entries: inWindow, calendar: calendar)

        var bars: [LifeChartDayBar] = []
        var cursor = calendar.startOfDay(for: interval.start)
        let lastDay = calendar.startOfDay(for: interval.end.addingTimeInterval(-1))
        while cursor <= lastDay {
            let dayEntries = entriesByDay[cursor] ?? []
            let band = reducer.reduce(entries: dayEntries)
            bars.append(LifeChartDayBar(
                day: cursor,
                band: band,
                entryCount: dayEntries.count,
                isMixedFeatures: mixedDays.contains(cursor)
            ))
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }

        let annotations = annotationProviders
            .flatMap { $0.annotations(entries: entries, window: interval, calendar: calendar) }
            .sorted { $0.day < $1.day }

        return LifeChartData(bars: bars, annotations: annotations, window: interval)
    }

    private static func resolveInterval(
        window: LifeChartWindow,
        entries: [MoodEntry],
        now: Date,
        calendar: Calendar
    ) -> DateInterval {
        let endDay = calendar.startOfDay(for: now)
        let endExclusive = calendar.date(byAdding: .day, value: 1, to: endDay) ?? endDay
        switch window {
        case .days(let n):
            let start = calendar.date(byAdding: .day, value: -(max(1, n) - 1), to: endDay) ?? endDay
            return DateInterval(start: start, end: endExclusive)
        case .all:
            let earliest = entries.map(\.timestamp).min() ?? endDay
            let start = calendar.startOfDay(for: earliest)
            return DateInterval(start: start, end: endExclusive)
        }
    }
}
