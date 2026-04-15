import XCTest
@testable import moodbound

final class MoodEntryValidationTests: XCTestCase {

    // MARK: - Happy path

    func testValidInputPasses() {
        XCTAssertNoThrow(try MoodEntryValidator.validate(
            moodLevel: 0, energy: 3, sleepHours: 7, irritability: 1, anxiety: 1, note: ""
        ))
    }

    func testBoundaryValuesMoodLevel() {
        XCTAssertNoThrow(try MoodEntryValidator.validate(
            moodLevel: -3, energy: 1, sleepHours: 0, irritability: 0, anxiety: 0, note: ""
        ))
        XCTAssertNoThrow(try MoodEntryValidator.validate(
            moodLevel: 3, energy: 5, sleepHours: 16, irritability: 3, anxiety: 3, note: ""
        ))
    }

    // MARK: - Mood level

    func testMoodLevelTooLow() {
        XCTAssertThrowsError(try MoodEntryValidator.validate(
            moodLevel: -4, energy: 3, sleepHours: 7, irritability: 0, anxiety: 0, note: ""
        )) { error in
            XCTAssertEqual(error as? MoodEntryValidationError, .moodLevelOutOfRange)
        }
    }

    func testMoodLevelTooHigh() {
        XCTAssertThrowsError(try MoodEntryValidator.validate(
            moodLevel: 4, energy: 3, sleepHours: 7, irritability: 0, anxiety: 0, note: ""
        )) { error in
            XCTAssertEqual(error as? MoodEntryValidationError, .moodLevelOutOfRange)
        }
    }

    // MARK: - Energy

    func testEnergyTooLow() {
        XCTAssertThrowsError(try MoodEntryValidator.validate(
            moodLevel: 0, energy: 0, sleepHours: 7, irritability: 0, anxiety: 0, note: ""
        )) { error in
            XCTAssertEqual(error as? MoodEntryValidationError, .energyOutOfRange)
        }
    }

    func testEnergyTooHigh() {
        XCTAssertThrowsError(try MoodEntryValidator.validate(
            moodLevel: 0, energy: 6, sleepHours: 7, irritability: 0, anxiety: 0, note: ""
        )) { error in
            XCTAssertEqual(error as? MoodEntryValidationError, .energyOutOfRange)
        }
    }

    // MARK: - Sleep

    func testSleepNegative() {
        XCTAssertThrowsError(try MoodEntryValidator.validate(
            moodLevel: 0, energy: 3, sleepHours: -1, irritability: 0, anxiety: 0, note: ""
        )) { error in
            XCTAssertEqual(error as? MoodEntryValidationError, .sleepOutOfRange)
        }
    }

    func testSleepTooHigh() {
        XCTAssertThrowsError(try MoodEntryValidator.validate(
            moodLevel: 0, energy: 3, sleepHours: 17, irritability: 0, anxiety: 0, note: ""
        )) { error in
            XCTAssertEqual(error as? MoodEntryValidationError, .sleepOutOfRange)
        }
    }

    // MARK: - Irritability

    func testIrritabilityOutOfRange() {
        XCTAssertThrowsError(try MoodEntryValidator.validate(
            moodLevel: 0, energy: 3, sleepHours: 7, irritability: -1, anxiety: 0, note: ""
        )) { error in
            XCTAssertEqual(error as? MoodEntryValidationError, .irritabilityOutOfRange)
        }
        XCTAssertThrowsError(try MoodEntryValidator.validate(
            moodLevel: 0, energy: 3, sleepHours: 7, irritability: 4, anxiety: 0, note: ""
        )) { error in
            XCTAssertEqual(error as? MoodEntryValidationError, .irritabilityOutOfRange)
        }
    }

    // MARK: - Anxiety

    func testAnxietyOutOfRange() {
        XCTAssertThrowsError(try MoodEntryValidator.validate(
            moodLevel: 0, energy: 3, sleepHours: 7, irritability: 0, anxiety: -1, note: ""
        )) { error in
            XCTAssertEqual(error as? MoodEntryValidationError, .anxietyOutOfRange)
        }
        XCTAssertThrowsError(try MoodEntryValidator.validate(
            moodLevel: 0, energy: 3, sleepHours: 7, irritability: 0, anxiety: 4, note: ""
        )) { error in
            XCTAssertEqual(error as? MoodEntryValidationError, .anxietyOutOfRange)
        }
    }

    // MARK: - Note length

    func testNoteAtLimit() {
        let note = String(repeating: "a", count: 2_000)
        XCTAssertNoThrow(try MoodEntryValidator.validate(
            moodLevel: 0, energy: 3, sleepHours: 7, irritability: 0, anxiety: 0, note: note
        ))
    }

    func testNoteOverLimit() {
        let note = String(repeating: "a", count: 2_001)
        XCTAssertThrowsError(try MoodEntryValidator.validate(
            moodLevel: 0, energy: 3, sleepHours: 7, irritability: 0, anxiety: 0, note: note
        )) { error in
            XCTAssertEqual(error as? MoodEntryValidationError, .noteTooLong)
        }
    }
}
