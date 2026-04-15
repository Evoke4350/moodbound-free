import Foundation
import SwiftData

@Model
final class TriggerFactor {
    var name: String
    var normalizedName: String
    var category: String
    var createdAt: Date
    @Relationship(deleteRule: .cascade, inverse: \TriggerEvent.trigger)
    var events: [TriggerEvent]

    init(
        name: String,
        category: String = "general",
        createdAt: Date = .now
    ) {
        self.name = name
        self.normalizedName = TriggerFactor.normalize(name)
        self.category = category
        self.createdAt = createdAt
        self.events = []
    }

    static func normalize(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

@Model
final class TriggerEvent {
    var timestamp: Date
    var intensity: Int
    var note: String
    @Relationship var trigger: TriggerFactor?
    @Relationship var moodEntry: MoodEntry?

    init(
        timestamp: Date,
        intensity: Int = 2,
        note: String = "",
        trigger: TriggerFactor? = nil,
        moodEntry: MoodEntry? = nil
    ) {
        self.timestamp = timestamp
        self.intensity = max(1, min(3, intensity))
        self.note = note
        self.trigger = trigger
        self.moodEntry = moodEntry
    }
}
