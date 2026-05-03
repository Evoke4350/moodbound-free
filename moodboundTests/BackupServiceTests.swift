import XCTest
import SwiftData
@testable import moodbound

@MainActor
final class BackupServiceTests: XCTestCase {
    private func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(
            for: MoodEntry.self,
            Medication.self,
            MedicationAdherenceEvent.self,
            TriggerFactor.self,
            TriggerEvent.self,
            SafetyPlan.self,
            SupportContact.self,
            ReminderSettings.self,
            OnboardingState.self,
            SurveyResponseRecord.self,
            configurations: config
        )
    }

    func testRoundTripPreservesOnboardingAndSurveys() throws {
        let source = try makeContainer()
        let sourceContext = source.mainContext

        // Seed a complete onboarding + surveys + multi-time reminder.
        try OnboardingPersistence.persist(
            context: sourceContext,
            diagnosis: .bipolarII,
            asrmAnswers: [
                "asrm-1-cheerfulness": 2,
                "asrm-2-confidence": 1,
                "asrm-3-sleep": 1,
                "asrm-4-speech": 0,
                "asrm-5-activity": 1,
            ],
            phq2Answers: ["phq2-1-interest": 2, "phq2-2-down": 2],
            reminderOptIn: true,
            reminderTime: Calendar.current.date(bySettingHour: 13, minute: 0, second: 0, of: .now)!
        )
        // Manually add an extra reminder time to exercise the multi-time
        // backup path the catch-up flow normally produces.
        let reminders = try sourceContext.fetch(FetchDescriptor<ReminderSettings>()).first!
        reminders.additionalMinutes = [60 * 20] // 8 PM extra slot

        let exported = try BackupService.exportJSON(context: sourceContext)

        let target = try makeContainer()
        try BackupService.importJSON(exported, context: target.mainContext)

        let onboarding = try target.mainContext.fetch(FetchDescriptor<OnboardingState>())
        XCTAssertEqual(onboarding.count, 1)
        XCTAssertTrue(onboarding[0].hasCompleted)
        XCTAssertEqual(onboarding[0].diagnosis, .bipolarII)
        XCTAssertTrue(onboarding[0].reminderOptedIn)

        let surveys = try target.mainContext.fetch(FetchDescriptor<SurveyResponseRecord>())
        XCTAssertEqual(surveys.count, 2)
        let kinds = Set(surveys.compactMap(\.kind))
        XCTAssertEqual(kinds, Set([.asrm, .phq2]))
        let asrm = surveys.first { $0.kind == .asrm }
        XCTAssertEqual(asrm?.totalScore, 5)

        let importedReminders = try target.mainContext.fetch(FetchDescriptor<ReminderSettings>())
        XCTAssertEqual(importedReminders.count, 1)
        XCTAssertEqual(importedReminders[0].hour, 13)
        XCTAssertEqual(importedReminders[0].additionalMinutes, [60 * 20])
        XCTAssertEqual(importedReminders[0].allTimes.count, 2)
    }

    func testV1PayloadStillImports() throws {
        // Exact shape of a payload produced by the previous version of
        // BackupService (no onboarding / surveys / additionalMinutes).
        // Asserts forward-compat for users restoring older backups.
        let v1 = """
        {
          "version": 1,
          "exportedAt": "2026-04-15T12:00:00Z",
          "entries": [],
          "medications": [],
          "triggers": [],
          "contacts": [],
          "reminderSettings": {
            "enabled": true,
            "hour": 20,
            "minute": 0,
            "message": "How are you feeling?"
          }
        }
        """

        let target = try makeContainer()
        try BackupService.importJSON(v1.data(using: .utf8)!, context: target.mainContext)

        let reminders = try target.mainContext.fetch(FetchDescriptor<ReminderSettings>())
        XCTAssertEqual(reminders.count, 1)
        XCTAssertEqual(reminders[0].additionalMinutes, [], "v1 payloads default additionalMinutes to empty")

        let onboarding = try target.mainContext.fetch(FetchDescriptor<OnboardingState>())
        XCTAssertTrue(onboarding.isEmpty, "v1 payload doesn't carry onboarding")

        let surveys = try target.mainContext.fetch(FetchDescriptor<SurveyResponseRecord>())
        XCTAssertTrue(surveys.isEmpty)
    }

    func testImportReplacesExistingOnboardingAndSurveyRows() throws {
        let target = try makeContainer()
        let context = target.mainContext

        // Seed pre-existing rows that should be wiped by the import.
        try OnboardingPersistence.persist(
            context: context,
            diagnosis: .undiagnosed,
            asrmAnswers: ["asrm-1-cheerfulness": 4, "asrm-2-confidence": 4, "asrm-3-sleep": 4, "asrm-4-speech": 4, "asrm-5-activity": 4],
            phq2Answers: [:],
            reminderOptIn: false,
            reminderTime: .now
        )

        // Import an empty payload (only required fields).
        let emptyPayload = """
        {
          "version": 2,
          "exportedAt": "2026-05-02T12:00:00Z",
          "entries": [],
          "medications": [],
          "triggers": [],
          "contacts": []
        }
        """
        try BackupService.importJSON(emptyPayload.data(using: .utf8)!, context: context)

        let onboarding = try context.fetch(FetchDescriptor<OnboardingState>())
        XCTAssertTrue(onboarding.isEmpty, "Import must wipe existing onboarding state")
        let surveys = try context.fetch(FetchDescriptor<SurveyResponseRecord>())
        XCTAssertTrue(surveys.isEmpty, "Import must wipe existing survey responses")
    }
}
