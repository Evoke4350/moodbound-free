import Foundation

/// Picks which entry on a given calendar day represents the day in the
/// chart. Strategy boundary because there's a known v2 follow-up — the
/// issue calls out a "split bar for mixed days" reducer that renders a
/// bar both above and below the zero line. Today only the worst-of-day
/// reducer ships; the protocol keeps the swap-in trivial.
protocol LifeChartDayReducer {
    /// Returns the band that should be drawn for this calendar day.
    /// Returning nil tells the chart to leave the day empty (handled by
    /// the service for the no-entries case; reducers normally produce a
    /// band whenever entries exist).
    func reduce(entries: [MoodEntry]) -> LifeChartBand?
}

/// NIMH-LCM convention: the day's bar reflects the worst-state-of-day,
/// chosen by maximum |moodLevel|. Ties resolve to the latest entry so
/// an evening dip after a balanced morning shows.
struct WorstOfDayReducer: LifeChartDayReducer {
    func reduce(entries: [MoodEntry]) -> LifeChartBand? {
        guard let dominant = entries
            .sorted(by: { $0.timestamp < $1.timestamp })
            .max(by: { abs($0.moodLevel) <= abs($1.moodLevel) })
        else { return nil }
        return LifeChartBand(moodLevel: dominant.moodLevel)
    }
}
