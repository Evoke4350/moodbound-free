import SwiftData
import XCTest
@testable import moodbound

final class MoodEntryPersistenceIntegrationTests: XCTestCase {
    func testCreateEditDeleteEntryPersistsAcrossContextOperations() throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: MoodEntry.self, configurations: configuration)
        let context = ModelContext(container)

        let created = try MoodEntry.makeValidated(
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            moodLevel: 1,
            energy: 4,
            sleepHours: 7.5,
            irritability: 1,
            anxiety: 1,
            note: "Initial note"
        )

        context.insert(created)
        try context.save()

        var descriptor = FetchDescriptor<MoodEntry>()
        descriptor.sortBy = [SortDescriptor(\.timestamp)]
        let afterCreate = try context.fetch(descriptor)
        XCTAssertEqual(afterCreate.count, 1)
        XCTAssertEqual(afterCreate.first?.moodLevel, 1)

        let createdEntry = try XCTUnwrap(afterCreate.first)
        try createdEntry.applyValidatedUpdate(
            timestamp: Date(timeIntervalSince1970: 1_700_000_100),
            moodLevel: -1,
            energy: 2,
            sleepHours: 8,
            irritability: 2,
            anxiety: 0,
            note: "Updated note"
        )
        try context.save()

        let afterUpdate = try context.fetch(descriptor)
        XCTAssertEqual(afterUpdate.first?.moodLevel, -1)
        XCTAssertEqual(afterUpdate.first?.note, "Updated note")

        context.delete(createdEntry)
        try context.save()

        let afterDelete = try context.fetch(descriptor)
        XCTAssertTrue(afterDelete.isEmpty)
    }
}
