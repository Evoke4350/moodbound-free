import Foundation
import SwiftData

/// Persisted survey administration. One row per completion. Stores the
/// raw per-question answers as JSON so the score can be recomputed if
/// the scoring rules ever evolve.
@Model
final class SurveyResponseRecord {
    var kindRawValue: String
    var totalScore: Int
    var bandLabel: String
    var screenPositive: Bool
    var completedAt: Date
    /// JSON-encoded `[String: Int]` — question id → raw answer.
    var answersJSON: String

    var kind: SurveyKind? {
        SurveyKind(rawValue: kindRawValue)
    }

    init(
        kind: SurveyKind,
        score: SurveyScore,
        answers: [String: Int],
        completedAt: Date = .now
    ) {
        self.kindRawValue = kind.rawValue
        self.totalScore = score.total
        self.bandLabel = score.band
        self.screenPositive = score.isScreenPositive
        self.completedAt = completedAt
        self.answersJSON = (try? String(
            data: JSONEncoder().encode(answers),
            encoding: .utf8
        )) ?? "{}"
    }

    var answers: [String: Int] {
        guard let data = answersJSON.data(using: .utf8) else { return [:] }
        return (try? JSONDecoder().decode([String: Int].self, from: data)) ?? [:]
    }
}
