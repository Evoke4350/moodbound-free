import Foundation
import SwiftData

enum BackupServiceError: LocalizedError {
    case invalidBackupData

    var errorDescription: String? {
        switch self {
        case .invalidBackupData:
            return "The backup file is invalid or corrupted."
        }
    }
}

enum BackupService {
    struct Payload: Codable {
        var version: Int
        var exportedAt: Date
        var entries: [EntryRecord]
        var medications: [MedicationRecord]
        var triggers: [TriggerRecord]
        var safetyPlan: SafetyPlanRecord?
        var contacts: [ContactRecord]
        var reminderSettings: ReminderRecord?
    }

    struct EntryRecord: Codable {
        var timestamp: Date
        var moodLevel: Int
        var energy: Int
        var sleepHours: Double
        var irritability: Int
        var anxiety: Int
        var note: String
        var weatherCity: String?
        var weatherCode: Int?
        var weatherSummary: String?
        var temperatureC: Double?
        var precipitationMM: Double?
        var restingHeartRate: Double?
        var hrvSDNN: Double?
        var stepCount: Int?
        var mindfulMinutes: Double?
        var medications: [String]
        var medsTaken: Bool
        var triggers: [String]
    }

    struct MedicationRecord: Codable {
        var name: String
        var dosage: String
        var scheduleNote: String
        var isActive: Bool
    }

    struct TriggerRecord: Codable {
        var name: String
        var category: String
    }

    struct SafetyPlanRecord: Codable {
        var warningSigns: String
        var copingStrategies: String
        var emergencySteps: String
    }

    struct ContactRecord: Codable {
        var name: String
        var relationship: String
        var phone: String
        var isPrimary: Bool
    }

    struct ReminderRecord: Codable {
        var enabled: Bool
        var hour: Int
        var minute: Int
        var message: String
    }

    static func exportJSON(context: ModelContext) throws -> Data {
        let entries = try context.fetch(FetchDescriptor<MoodEntry>())
        let medications = try context.fetch(FetchDescriptor<Medication>())
        let triggers = try context.fetch(FetchDescriptor<TriggerFactor>())
        let plans = try context.fetch(FetchDescriptor<SafetyPlan>())
        let contacts = try context.fetch(FetchDescriptor<SupportContact>())
        let reminders = try context.fetch(FetchDescriptor<ReminderSettings>())

        let payload = Payload(
            version: 1,
            exportedAt: Date(),
            entries: entries.map { entry in
                EntryRecord(
                    timestamp: entry.timestamp,
                    moodLevel: entry.moodLevel,
                    energy: entry.energy,
                    sleepHours: entry.sleepHours,
                    irritability: entry.irritability,
                    anxiety: entry.anxiety,
                    note: entry.note,
                    weatherCity: entry.weatherCity,
                    weatherCode: entry.weatherCode,
                    weatherSummary: entry.weatherSummary,
                    temperatureC: entry.temperatureC,
                    precipitationMM: entry.precipitationMM,
                    restingHeartRate: entry.restingHeartRate,
                    hrvSDNN: entry.hrvSDNN,
                    stepCount: entry.stepCount,
                    mindfulMinutes: entry.mindfulMinutes,
                    medications: entry.medicationNames,
                    medsTaken: entry.medicationAdherenceEvents.contains(where: \.taken),
                    triggers: entry.triggerEvents.compactMap { $0.trigger?.name }
                )
            },
            medications: medications.map { medication in
                MedicationRecord(
                    name: medication.name,
                    dosage: medication.dosage,
                    scheduleNote: medication.scheduleNote,
                    isActive: medication.isActive
                )
            },
            triggers: triggers.map { trigger in
                TriggerRecord(name: trigger.name, category: trigger.category)
            },
            safetyPlan: plans.first.map {
                SafetyPlanRecord(
                    warningSigns: $0.warningSigns,
                    copingStrategies: $0.copingStrategies,
                    emergencySteps: $0.emergencySteps
                )
            },
            contacts: contacts.map {
                ContactRecord(
                    name: $0.name,
                    relationship: $0.relationship,
                    phone: $0.phone,
                    isPrimary: $0.isPrimary
                )
            },
            reminderSettings: reminders.first.map {
                ReminderRecord(
                    enabled: $0.enabled,
                    hour: $0.hour,
                    minute: $0.minute,
                    message: $0.message
                )
            }
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(payload)
    }

    static func importJSON(_ data: Data, context: ModelContext) throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        guard let payload = try? decoder.decode(Payload.self, from: data) else {
            throw BackupServiceError.invalidBackupData
        }

        try deleteAll(context: context, type: MoodEntry.self)
        try deleteAll(context: context, type: MedicationAdherenceEvent.self)
        try deleteAll(context: context, type: TriggerEvent.self)
        try deleteAll(context: context, type: Medication.self)
        try deleteAll(context: context, type: TriggerFactor.self)
        try deleteAll(context: context, type: SafetyPlan.self)
        try deleteAll(context: context, type: SupportContact.self)
        try deleteAll(context: context, type: ReminderSettings.self)

        var medicationMap: [String: Medication] = [:]
        for record in payload.medications {
            let medication = Medication(
                name: record.name,
                dosage: record.dosage,
                scheduleNote: record.scheduleNote,
                isActive: record.isActive
            )
            context.insert(medication)
            medicationMap[Medication.normalize(record.name)] = medication
        }

        var triggerMap: [String: TriggerFactor] = [:]
        for record in payload.triggers {
            let trigger = TriggerFactor(name: record.name, category: record.category)
            context.insert(trigger)
            triggerMap[TriggerFactor.normalize(record.name)] = trigger
        }

        for record in payload.entries {
            let entry = try MoodEntry.makeValidated(
                timestamp: record.timestamp,
                moodLevel: record.moodLevel,
                energy: record.energy,
                sleepHours: record.sleepHours,
                irritability: record.irritability,
                anxiety: record.anxiety,
                note: record.note,
                weatherCity: record.weatherCity,
                weatherCode: record.weatherCode,
                weatherSummary: record.weatherSummary,
                temperatureC: record.temperatureC,
                precipitationMM: record.precipitationMM,
                restingHeartRate: record.restingHeartRate,
                hrvSDNN: record.hrvSDNN,
                stepCount: record.stepCount,
                mindfulMinutes: record.mindfulMinutes
            )
            context.insert(entry)

            for medicationName in record.medications {
                let key = Medication.normalize(medicationName)
                let medication = medicationMap[key] ?? {
                    let created = Medication(name: medicationName)
                    context.insert(created)
                    medicationMap[key] = created
                    return created
                }()

                let event = MedicationAdherenceEvent(
                    timestamp: record.timestamp,
                    taken: record.medsTaken,
                    note: "Imported from backup",
                    medication: medication,
                    moodEntry: entry
                )
                context.insert(event)
                entry.medicationAdherenceEvents.append(event)
            }

            for triggerName in record.triggers {
                let key = TriggerFactor.normalize(triggerName)
                let trigger = triggerMap[key] ?? {
                    let created = TriggerFactor(name: triggerName)
                    context.insert(created)
                    triggerMap[key] = created
                    return created
                }()

                let event = TriggerEvent(
                    timestamp: record.timestamp,
                    intensity: 2,
                    note: "Imported from backup",
                    trigger: trigger,
                    moodEntry: entry
                )
                context.insert(event)
                entry.triggerEvents.append(event)
            }
        }

        if let plan = payload.safetyPlan {
            context.insert(
                SafetyPlan(
                    warningSigns: plan.warningSigns,
                    copingStrategies: plan.copingStrategies,
                    emergencySteps: plan.emergencySteps
                )
            )
        }

        for contact in payload.contacts {
            context.insert(
                SupportContact(
                    name: contact.name,
                    relationship: contact.relationship,
                    phone: contact.phone,
                    isPrimary: contact.isPrimary
                )
            )
        }

        if let reminder = payload.reminderSettings {
            context.insert(
                ReminderSettings(
                    enabled: reminder.enabled,
                    hour: reminder.hour,
                    minute: reminder.minute,
                    message: reminder.message
                )
            )
        }

        try context.save()
    }

    private static func deleteAll<T: PersistentModel>(context: ModelContext, type: T.Type) throws {
        let all = try context.fetch(FetchDescriptor<T>())
        for record in all {
            context.delete(record)
        }
    }
}
