import Foundation

/// One of the 4 NIMH-LCM-p severity bands per pole, plus euthymic.
/// The full NIMH-LCM-S/P (Leverich & Post 2002) defines 5 bands per pole —
/// mild (±1), low-moderate (±2), high-moderate (±3), severe (±4) — keyed
/// to the degree of functional impairment. Moodbound's -3..+3 self-rating
/// only carries 3 bands per pole, so we collapse to 4 visible bands and
/// drop NIMH's subsyndromal "mild" tier: a Moodbound user who picks
/// "mild depression" is already past the subsyndromal threshold the
/// LCM uses, so it maps to "low moderate" rather than "mild". The
/// chart legend documents the collapse so clinicians can audit.
///
/// Reference: Leverich GS, Post RM. The NIMH life chart manual for
/// recurrent affective illness: the LCM-S/P (self-version/prospective).
/// 2002. Validation: Denicoff et al., J Affect Disord 2000
/// (https://pubmed.ncbi.nlm.nih.gov/11097079/).
enum LifeChartBand: Int, CaseIterable {
    case severeDepression = -4
    case moderateHighDepression = -3
    case moderateLowDepression = -2
    case euthymic = 0
    case moderateLowElevation = 2
    case moderateHighElevation = 3
    case severeMania = 4

    enum Pole {
        case depression
        case euthymic
        case elevation
    }

    init(moodLevel: Int) {
        switch moodLevel {
        case ..<(-2): self = .severeDepression
        case -2: self = .moderateHighDepression
        case -1: self = .moderateLowDepression
        case 1: self = .moderateLowElevation
        case 2: self = .moderateHighElevation
        case 3...: self = .severeMania
        default: self = .euthymic
        }
    }

    /// Bar height 0...1, consumed by the chart renderer.
    var barWeight: Double {
        switch self {
        case .euthymic: return 0
        case .moderateLowDepression, .moderateLowElevation: return 0.5
        case .moderateHighDepression, .moderateHighElevation: return 0.75
        case .severeDepression, .severeMania: return 1.0
        }
    }

    var pole: Pole {
        if rawValue < 0 { return .depression }
        if rawValue > 0 { return .elevation }
        return .euthymic
    }

    /// Short label for VoiceOver and tooltip surfaces.
    var label: String {
        switch self {
        case .severeDepression: return "Severe depression"
        case .moderateHighDepression: return "Moderate-high depression"
        case .moderateLowDepression: return "Moderate-low depression"
        case .euthymic: return "Euthymic"
        case .moderateLowElevation: return "Moderate-low elevation"
        case .moderateHighElevation: return "Moderate-high elevation"
        case .severeMania: return "Severe mania"
        }
    }
}
