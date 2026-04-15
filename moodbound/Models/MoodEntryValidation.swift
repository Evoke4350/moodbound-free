import Foundation

enum MoodEntryValidationError: LocalizedError {
    case moodLevelOutOfRange
    case energyOutOfRange
    case sleepOutOfRange
    case irritabilityOutOfRange
    case anxietyOutOfRange
    case noteTooLong

    var errorDescription: String? {
        switch self {
        case .moodLevelOutOfRange:
            return "Mood must be between -3 and 3."
        case .energyOutOfRange:
            return "Energy must be between 1 and 5."
        case .sleepOutOfRange:
            return "Sleep must be between 0 and 16 hours."
        case .irritabilityOutOfRange:
            return "Irritability must be between 0 and 3."
        case .anxietyOutOfRange:
            return "Anxiety must be between 0 and 3."
        case .noteTooLong:
            return "Notes must be 2,000 characters or fewer."
        }
    }
}

enum MoodEntryValidator {
    static let noteLimit = 2_000

    static func validate(
        moodLevel: Int,
        energy: Int,
        sleepHours: Double,
        irritability: Int,
        anxiety: Int,
        note: String
    ) throws {
        guard (-3...3).contains(moodLevel) else { throw MoodEntryValidationError.moodLevelOutOfRange }
        guard (1...5).contains(energy) else { throw MoodEntryValidationError.energyOutOfRange }
        guard (0...16).contains(sleepHours) else { throw MoodEntryValidationError.sleepOutOfRange }
        guard (0...3).contains(irritability) else { throw MoodEntryValidationError.irritabilityOutOfRange }
        guard (0...3).contains(anxiety) else { throw MoodEntryValidationError.anxietyOutOfRange }
        guard note.count <= noteLimit else { throw MoodEntryValidationError.noteTooLong }
    }
}
