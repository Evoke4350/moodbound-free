import Foundation

enum NVCOutputGuard {
    private static let fallback = """
    **Observation:** I noticed something happened between us.

    **Feeling:** I'm feeling unsettled about it.

    **Need:** I need some understanding and connection.

    **Request:** Could we take a moment to talk about this openly?
    """

    /// Suspicious patterns that suggest prompt injection succeeded.
    private static let blockedPatterns: [String] = [
        "```",             // code blocks
        "http://",         // URLs
        "https://",
        "<script",         // HTML/JS injection
        "ignore previous",
        "ignore all",
        "disregard",
        "as an ai",
        "i am a language model",
        "sure, here",      // compliance preamble
        "certainly!",
    ]

    /// Returns the original text if it looks like valid NVC, otherwise a safe fallback.
    static func validate(_ text: String) -> String {
        let lower = text.lowercased()

        // Check for blocked patterns
        for pattern in blockedPatterns {
            if lower.contains(pattern) {
                return fallback
            }
        }

        // Expect at least two of the four NVC sections
        let sectionKeywords = ["observation", "feeling", "need", "request"]
        let matchCount = sectionKeywords.filter { lower.contains($0) }.count
        if matchCount < 2 {
            return fallback
        }

        return text
    }
}
