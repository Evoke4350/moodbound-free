import XCTest
import SwiftData
@testable import moodbound

final class SurveyScorerTests: XCTestCase {
    func testASRMSumsAcrossFiveQuestions() {
        let answers = [
            "asrm-1-cheerfulness": 2,
            "asrm-2-confidence": 1,
            "asrm-3-sleep": 0,
            "asrm-4-speech": 3,
            "asrm-5-activity": 4,
        ]
        let score = SurveyScorer.score(kind: .asrm, responses: answers)
        XCTAssertEqual(score.total, 10)
        XCTAssertTrue(score.isScreenPositive, "ASRM 10 should screen positive (≥6)")
    }

    func testASRMBelowThresholdNotPositive() {
        let answers = [
            "asrm-1-cheerfulness": 1,
            "asrm-2-confidence": 1,
            "asrm-3-sleep": 1,
            "asrm-4-speech": 1,
            "asrm-5-activity": 1,
        ]
        let score = SurveyScorer.score(kind: .asrm, responses: answers)
        XCTAssertEqual(score.total, 5)
        XCTAssertFalse(score.isScreenPositive)
    }

    func testPHQ2ScreenPositiveAtThree() {
        let answers = ["phq2-1-interest": 2, "phq2-2-down": 1]
        let score = SurveyScorer.score(kind: .phq2, responses: answers)
        XCTAssertEqual(score.total, 3)
        XCTAssertTrue(score.isScreenPositive)
    }

    func testMissingAnswersTreatedAsZero() {
        let score = SurveyScorer.score(kind: .asrm, responses: [:])
        XCTAssertEqual(score.total, 0)
        XCTAssertFalse(score.isScreenPositive)
    }

    func testOutOfRangeAnswersClampedToMaxOrZero() {
        let answers = [
            "asrm-1-cheerfulness": 99,
            "asrm-2-confidence": -50,
            "asrm-3-sleep": 4,
            "asrm-4-speech": 0,
            "asrm-5-activity": 0,
        ]
        let score = SurveyScorer.score(kind: .asrm, responses: answers)
        // 4 (clamped) + 0 (clamped) + 4 + 0 + 0 = 8
        XCTAssertEqual(score.total, 8)
    }

    func testBandLabelsReturnedFromCatalog() {
        let asrm = SurveyScorer.score(kind: .asrm, responses: [
            "asrm-1-cheerfulness": 4,
            "asrm-2-confidence": 4,
            "asrm-3-sleep": 4,
            "asrm-4-speech": 4,
            "asrm-5-activity": 4,
        ])
        XCTAssertEqual(asrm.total, 20)
        XCTAssertEqual(asrm.band, "Possible mania")
    }
}

final class OnboardingPersistenceTests: XCTestCase {
    @MainActor
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

    @MainActor
    func testFinishingPersistsStateSurveysAndReminder() throws {
        let container = try makeContainer()
        let context = container.mainContext

        try OnboardingPersistence.persist(
            context: context,
            diagnosis: .bipolarII,
            asrmAnswers: [
                "asrm-1-cheerfulness": 2,
                "asrm-2-confidence": 2,
                "asrm-3-sleep": 1,
                "asrm-4-speech": 1,
                "asrm-5-activity": 1,
            ],
            phq2Answers: ["phq2-1-interest": 2, "phq2-2-down": 2],
            reminderOptIn: true,
            reminderTime: Calendar.current.date(bySettingHour: 21, minute: 30, second: 0, of: .now)!
        )

        let states = try context.fetch(FetchDescriptor<OnboardingState>())
        XCTAssertEqual(states.count, 1)
        XCTAssertTrue(states[0].hasCompleted)
        XCTAssertEqual(states[0].diagnosis, .bipolarII)
        XCTAssertEqual(states[0].reminderHour, 21)
        XCTAssertEqual(states[0].reminderMinute, 30)
        XCTAssertTrue(states[0].reminderOptedIn)

        let surveys = try context.fetch(FetchDescriptor<SurveyResponseRecord>())
        XCTAssertEqual(surveys.count, 2)
        let kinds = Set(surveys.compactMap(\.kind))
        XCTAssertEqual(kinds, Set([.asrm, .phq2]))

        let reminders = try context.fetch(FetchDescriptor<ReminderSettings>())
        XCTAssertEqual(reminders.count, 1)
        XCTAssertTrue(reminders[0].enabled)
        XCTAssertEqual(reminders[0].hour, 21)
    }

    @MainActor
    func testPersistingTwiceUpdatesExistingState() throws {
        let container = try makeContainer()
        let context = container.mainContext

        try OnboardingPersistence.persist(
            context: context,
            diagnosis: .undiagnosed,
            asrmAnswers: [:],
            phq2Answers: [:],
            reminderOptIn: false,
            reminderTime: .now
        )
        try OnboardingPersistence.persist(
            context: context,
            diagnosis: .bipolarI,
            asrmAnswers: [:],
            phq2Answers: [:],
            reminderOptIn: false,
            reminderTime: .now
        )

        let states = try context.fetch(FetchDescriptor<OnboardingState>())
        XCTAssertEqual(states.count, 1, "Re-running onboarding must update the same row, not append")
        XCTAssertEqual(states[0].diagnosis, .bipolarI)
    }

    @MainActor
    func testNoSurveyRecordsWhenAnswersEmpty() throws {
        let container = try makeContainer()
        let context = container.mainContext

        try OnboardingPersistence.persist(
            context: context,
            diagnosis: nil,
            asrmAnswers: [:],
            phq2Answers: [:],
            reminderOptIn: false,
            reminderTime: .now
        )

        let surveys = try context.fetch(FetchDescriptor<SurveyResponseRecord>())
        XCTAssertEqual(surveys.count, 0)
    }
}
