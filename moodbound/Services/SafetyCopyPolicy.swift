import Foundation

enum SafetyCopyPolicy {
    private static let prohibitedFragments: [String] = [
        "you are definitely",
        "no concern",
        "it's nothing",
        "just calm down",
    ]

    static func sanitize(_ messages: [String]) -> [String] {
        messages.map(sanitizeMessage(_:))
    }

    static func sanitizeMessage(_ message: String) -> String {
        var cleaned = message.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = cleaned.lowercased()
        for fragment in prohibitedFragments where lower.contains(fragment) {
            cleaned = L10n.tr("safety.sanitized_fallback")
            break
        }
        return cleaned
    }

    static func crisisBannerText(for severity: SafetySeverity) -> String? {
        switch severity {
        case .critical:
            return L10n.tr("safety.critical_crisis")
        case .high:
            return L10n.tr("safety.high_crisis")
        case .elevated, .none:
            return nil
        }
    }
}
