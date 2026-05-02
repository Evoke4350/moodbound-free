import Foundation

/// One day's worth of charted data. `band == nil` means no entry was
/// logged that day — renderer draws a faint baseline tick so the gap is
/// visible.
struct LifeChartDayBar: Equatable {
    let day: Date
    let band: LifeChartBand?
    let entryCount: Int
    let isMixedFeatures: Bool
}
