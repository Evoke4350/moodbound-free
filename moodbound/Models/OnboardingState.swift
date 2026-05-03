import Foundation
import SwiftData

enum DiagnosisSelfReport: String, CaseIterable, Codable, Identifiable {
    case bipolarI
    case bipolarII
    case cyclothymic
    case undiagnosed
    case depressionOnly
    case preferNotToSay

    var id: String { rawValue }

    var label: String {
        switch self {
        case .bipolarI: return "Bipolar I"
        case .bipolarII: return "Bipolar II"
        case .cyclothymic: return "Cyclothymic"
        case .undiagnosed: return "Undiagnosed / exploring"
        case .depressionOnly: return "Depression only"
        case .preferNotToSay: return "Prefer not to say"
        }
    }
}

/// Single-row record tracking onboarding completion plus the
/// information collected during the flow. Kept as a SwiftData entity
/// (not just AppStorage) so future periodic re-administration of the
/// baseline surveys can compare against the install-time scores.
@Model
final class OnboardingState {
    var hasCompleted: Bool
    var completedAt: Date?
    var diagnosisRawValue: String?
    /// True if the user opted in to the daily reminder during onboarding.
    var reminderOptedIn: Bool
    var reminderHour: Int
    var reminderMinute: Int

    init(
        hasCompleted: Bool = false,
        completedAt: Date? = nil,
        diagnosisRawValue: String? = nil,
        reminderOptedIn: Bool = false,
        reminderHour: Int = 20,
        reminderMinute: Int = 0
    ) {
        self.hasCompleted = hasCompleted
        self.completedAt = completedAt
        self.diagnosisRawValue = diagnosisRawValue
        self.reminderOptedIn = reminderOptedIn
        self.reminderHour = reminderHour
        self.reminderMinute = reminderMinute
    }

    var diagnosis: DiagnosisSelfReport? {
        diagnosisRawValue.flatMap(DiagnosisSelfReport.init(rawValue:))
    }
}
