import Foundation

/// Event marker rendered on the chart's zero line. Adding a new
/// annotation type means adding a case here and a `LifeChartAnnotationProvider`
/// implementation to emit it.
enum LifeChartAnnotation: Equatable {
    case medicationStarted(name: String, day: Date)
    case medicationStopped(name: String, day: Date)
    case highIntensityTrigger(name: String, intensity: Int, day: Date)

    var day: Date {
        switch self {
        case .medicationStarted(_, let day),
             .medicationStopped(_, let day),
             .highIntensityTrigger(_, _, let day):
            return day
        }
    }
}
