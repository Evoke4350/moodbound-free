import SwiftUI

enum MoodScale: Int, CaseIterable, Identifiable, Codable {
    case severeDepression = -3
    case moderateDepression = -2
    case mildDepression = -1
    case balanced = 0
    case mildElevation = 1
    case hypomania = 2
    case mania = 3

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .severeDepression: return "Severe Depression"
        case .moderateDepression: return "Moderate Depression"
        case .mildDepression: return "Mild Depression"
        case .balanced: return "Balanced"
        case .mildElevation: return "Mild Elevation"
        case .hypomania: return "Hypomania"
        case .mania: return "Mania"
        }
    }

    var shortLabel: String {
        switch self {
        case .severeDepression: return "Dep"
        case .moderateDepression: return "Low"
        case .mildDepression: return "Low"
        case .balanced: return "Bal"
        case .mildElevation: return "Up"
        case .hypomania: return "High"
        case .mania: return "Mania"
        }
    }

    var emoji: String {
        switch self {
        case .severeDepression: return "😞"
        case .moderateDepression: return "😔"
        case .mildDepression: return "😕"
        case .balanced: return "😌"
        case .mildElevation: return "🙂"
        case .hypomania: return "😃"
        case .mania: return "🤯"
        }
    }

    var color: Color {
        switch self {
        case .severeDepression: return .indigo
        case .moderateDepression: return .blue
        case .mildDepression: return .cyan
        case .balanced: return .green
        case .mildElevation: return .yellow
        case .hypomania: return .orange
        case .mania: return .red
        }
    }
}
