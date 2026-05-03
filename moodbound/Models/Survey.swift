import Foundation

/// Validated screening / monitoring instruments. The same definition
/// powers the install-time baseline AND any future periodic
/// re-administration (e.g. weekly ASRM check-in). Add a new instrument
/// by extending the `SurveyKind` enum and providing its `definition`.
enum SurveyKind: String, CaseIterable, Codable, Identifiable {
    /// Altman Self-Rating Mania Scale. 5 items, 0-4 each. ≥6 screens
    /// positive for mania/hypomania (Altman 1997).
    case asrm
    /// Patient Health Questionnaire 2-item depression screener. 2 items,
    /// 0-3 each. ≥3 screens positive for depression (Kroenke 2003).
    case phq2

    var id: String { rawValue }
}

struct SurveyQuestion: Equatable, Identifiable {
    let id: String
    let prompt: String
    /// Labels for the 0..maxValue answer options, indexed by score.
    let answerLabels: [String]
    var maxValue: Int { answerLabels.count - 1 }
}

struct SurveyDefinition {
    let kind: SurveyKind
    let title: String
    let intro: String
    let questions: [SurveyQuestion]
    /// Threshold at or above which the survey is flagged "screen positive".
    let screenPositiveThreshold: Int
    /// Bands surfaced after scoring (lower-inclusive ranges).
    let scoreBands: [(range: ClosedRange<Int>, label: String)]

    var maxScore: Int { questions.reduce(0) { $0 + $1.maxValue } }
}

enum SurveyCatalog {
    static func definition(for kind: SurveyKind) -> SurveyDefinition {
        switch kind {
        case .asrm: return asrm
        case .phq2: return phq2
        }
    }

    private static let asrm = SurveyDefinition(
        kind: .asrm,
        title: "Altman Self-Rating Mania Scale",
        intro: "Five quick questions about the past week. Answers help anchor your future check-ins.",
        questions: [
            SurveyQuestion(
                id: "asrm-1-cheerfulness",
                prompt: "Over the past week…",
                answerLabels: [
                    "I do not feel happier or more cheerful than usual.",
                    "I occasionally feel happier or more cheerful than usual.",
                    "I often feel happier or more cheerful than usual.",
                    "I feel happier or more cheerful than usual most of the time.",
                    "I feel happier or more cheerful than usual all of the time.",
                ]
            ),
            SurveyQuestion(
                id: "asrm-2-confidence",
                prompt: "Over the past week…",
                answerLabels: [
                    "I do not feel more self-confident than usual.",
                    "I occasionally feel more self-confident than usual.",
                    "I often feel more self-confident than usual.",
                    "I feel more self-confident than usual most of the time.",
                    "I feel extremely self-confident all of the time.",
                ]
            ),
            SurveyQuestion(
                id: "asrm-3-sleep",
                prompt: "Over the past week…",
                answerLabels: [
                    "I do not need less sleep than usual.",
                    "I occasionally need less sleep than usual.",
                    "I often need less sleep than usual.",
                    "I frequently need less sleep than usual.",
                    "I can go all day and night without any sleep and not feel tired.",
                ]
            ),
            SurveyQuestion(
                id: "asrm-4-speech",
                prompt: "Over the past week…",
                answerLabels: [
                    "I do not talk more than usual.",
                    "I occasionally talk more than usual.",
                    "I often talk more than usual.",
                    "I frequently talk more than usual.",
                    "I talk constantly and cannot be interrupted.",
                ]
            ),
            SurveyQuestion(
                id: "asrm-5-activity",
                prompt: "Over the past week…",
                answerLabels: [
                    "I have not been more active than usual.",
                    "I have occasionally been more active than usual.",
                    "I have often been more active than usual.",
                    "I have frequently been more active than usual.",
                    "I am constantly active or on the go.",
                ]
            ),
        ],
        screenPositiveThreshold: 6,
        scoreBands: [
            (0...5, "Below screening threshold"),
            (6...11, "Possible hypomania"),
            (12...20, "Possible mania"),
        ]
    )

    private static let phq2 = SurveyDefinition(
        kind: .phq2,
        title: "Mood Screen (PHQ-2)",
        intro: "Two questions about the past two weeks. A quick snapshot of low-mood symptoms.",
        questions: [
            SurveyQuestion(
                id: "phq2-1-interest",
                prompt: "Over the past two weeks, how often have you been bothered by little interest or pleasure in doing things?",
                answerLabels: [
                    "Not at all",
                    "Several days",
                    "More than half the days",
                    "Nearly every day",
                ]
            ),
            SurveyQuestion(
                id: "phq2-2-down",
                prompt: "Over the past two weeks, how often have you been feeling down, depressed, or hopeless?",
                answerLabels: [
                    "Not at all",
                    "Several days",
                    "More than half the days",
                    "Nearly every day",
                ]
            ),
        ],
        screenPositiveThreshold: 3,
        scoreBands: [
            (0...2, "Below screening threshold"),
            (3...6, "Positive screen — consider PHQ-9"),
        ]
    )
}

struct SurveyScore: Equatable {
    let kind: SurveyKind
    let total: Int
    let band: String
    let isScreenPositive: Bool
}

enum SurveyScorer {
    /// Scores `responses` (one entry per question, indexed by question
    /// id) against the survey definition. Missing or out-of-range
    /// answers are clamped to 0.
    static func score(kind: SurveyKind, responses: [String: Int]) -> SurveyScore {
        let definition = SurveyCatalog.definition(for: kind)
        let total = definition.questions.reduce(0) { sum, question in
            let raw = responses[question.id] ?? 0
            let clamped = max(0, min(question.maxValue, raw))
            return sum + clamped
        }
        let band = definition.scoreBands.first { $0.range.contains(total) }?.label
            ?? "Score \(total)"
        return SurveyScore(
            kind: kind,
            total: total,
            band: band,
            isScreenPositive: total >= definition.screenPositiveThreshold
        )
    }
}
