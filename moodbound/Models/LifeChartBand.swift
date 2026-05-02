import Foundation

/// One of the 4 NIMH-LCM-p severity bands per pole, plus euthymic.
/// Moodbound's -3..+3 mood scale maps onto these so the chart uses the
/// same vocabulary clinicians read in research literature and intake
/// paperwork.
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
