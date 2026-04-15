import XCTest
@testable import moodbound

final class HistorySelectionServiceTests: XCTestCase {
    func testNearestEntryReturnsClosestTimestamp() {
        let entries = Array(RealisticMoodDatasetFactory.makeScenario(days: 12).entries.suffix(3))
        let anchor = entries[1].timestamp
        let target = anchor
        entries[0].timestamp = anchor.addingTimeInterval(-3 * 3_600)
        entries[1].timestamp = anchor.addingTimeInterval(10 * 60)
        entries[2].timestamp = anchor.addingTimeInterval(-24 * 3_600)

        let nearest = HistorySelectionService.nearestEntry(to: target, entries: entries)
        XCTAssertEqual(nearest?.timestamp, entries[1].timestamp)
    }

    func testNearestEntryReturnsNilForEmptyInput() {
        let nearest = HistorySelectionService.nearestEntry(to: Date(), entries: [])
        XCTAssertNil(nearest)
    }
}
