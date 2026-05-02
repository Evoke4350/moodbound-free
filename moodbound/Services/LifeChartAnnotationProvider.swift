import Foundation

/// Emits chart annotations from the entry stream. New event types
/// (life events, hospitalizations, dose changes) attach by adding a
/// new conformer; the chart service composes whichever providers it's
/// handed.
///
/// Contract for conformers: the window passed in is day-aligned
/// (`start == startOfDay(start)`, `end == startOfDay(start + N days)`),
/// matching how `LifeChartService` builds the bar grid. Each emitted
/// annotation's `day` must equal `startOfDay(eventTimestamp)` and must
/// fall within the window so it can be placed on a bar.
protocol LifeChartAnnotationProvider {
    func annotations(
        entries: [MoodEntry],
        window: DateInterval,
        calendar: Calendar
    ) -> [LifeChartAnnotation]
}

/// Emits a `medicationStarted` annotation on the first day a medication
/// shows up in adherence events, and a `medicationStopped` annotation
/// on the last day it appears — but only when that "last day" is at
/// least `gracePeriodDays` before the window end. Without the grace
/// period, every currently-active med would falsely show "stopped" on
/// its most recent log day.
struct MedicationChangeProvider: LifeChartAnnotationProvider {
    let gracePeriodDays: Int

    init(gracePeriodDays: Int = 14) {
        self.gracePeriodDays = max(1, gracePeriodDays)
    }

    func annotations(
        entries: [MoodEntry],
        window: DateInterval,
        calendar: Calendar
    ) -> [LifeChartAnnotation] {
        let events = entries
            .flatMap(\.medicationAdherenceEvents)
            .sorted { $0.timestamp < $1.timestamp }

        var first: [String: (date: Date, name: String)] = [:]
        var last: [String: (date: Date, name: String)] = [:]
        for event in events {
            guard let med = event.medication else { continue }
            let key = med.normalizedName
            if first[key] == nil {
                first[key] = (event.timestamp, med.name)
            }
            last[key] = (event.timestamp, med.name)
        }

        let stopCutoff = window.end.addingTimeInterval(-Double(gracePeriodDays) * 86_400)
        var output: [LifeChartAnnotation] = []
        for (key, start) in first where window.contains(start.date) {
            output.append(.medicationStarted(
                name: start.name,
                day: calendar.startOfDay(for: start.date)
            ))
            if let stop = last[key], stop.date < stopCutoff, window.contains(stop.date) {
                output.append(.medicationStopped(
                    name: stop.name,
                    day: calendar.startOfDay(for: stop.date)
                ))
            }
        }
        return output.sorted { $0.day < $1.day }
    }
}

/// Emits an annotation per high-intensity trigger event. `intensity` is
/// 1...3 (capped in `TriggerEvent.init`), so the threshold default of 3
/// surfaces only the most-intense triggers.
struct HighIntensityTriggerProvider: LifeChartAnnotationProvider {
    let intensityThreshold: Int

    init(intensityThreshold: Int = 3) {
        self.intensityThreshold = intensityThreshold
    }

    func annotations(
        entries: [MoodEntry],
        window: DateInterval,
        calendar: Calendar
    ) -> [LifeChartAnnotation] {
        entries
            .flatMap(\.triggerEvents)
            .filter { $0.intensity >= intensityThreshold && window.contains($0.timestamp) }
            .compactMap { event in
                guard let name = event.trigger?.name else { return nil }
                return LifeChartAnnotation.highIntensityTrigger(
                    name: name,
                    intensity: event.intensity,
                    day: calendar.startOfDay(for: event.timestamp)
                )
            }
    }
}
