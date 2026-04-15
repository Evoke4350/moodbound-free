import Foundation

enum HistorySelectionService {
    static func nearestEntry(to date: Date, entries: [MoodEntry]) -> MoodEntry? {
        entries.min {
            abs($0.timestamp.timeIntervalSince(date)) < abs($1.timestamp.timeIntervalSince(date))
        }
    }
}
