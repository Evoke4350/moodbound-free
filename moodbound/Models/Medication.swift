import Foundation
import SwiftData

@Model
final class Medication {
    var name: String
    var normalizedName: String
    var dosage: String
    var scheduleNote: String
    var isActive: Bool
    @Relationship(deleteRule: .cascade, inverse: \MedicationAdherenceEvent.medication)
    var adherenceEvents: [MedicationAdherenceEvent]

    init(
        name: String,
        dosage: String = "",
        scheduleNote: String = "",
        isActive: Bool = true
    ) {
        self.name = name
        self.normalizedName = Medication.normalize(name)
        self.dosage = dosage
        self.scheduleNote = scheduleNote
        self.isActive = isActive
        self.adherenceEvents = []
    }

    static func normalize(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

@Model
final class MedicationAdherenceEvent {
    var timestamp: Date
    var taken: Bool
    var note: String
    @Relationship var medication: Medication?
    @Relationship var moodEntry: MoodEntry?

    init(
        timestamp: Date,
        taken: Bool,
        note: String = "",
        medication: Medication? = nil,
        moodEntry: MoodEntry? = nil
    ) {
        self.timestamp = timestamp
        self.taken = taken
        self.note = note
        self.medication = medication
        self.moodEntry = moodEntry
    }
}
