import Foundation

/// Single source of truth for "What's New" highlights shown after an
/// upgrade. Add a new `Release` entry per version that has user-visible
/// changes. Releases without an entry never trigger the sheet.
struct WhatsNewRelease: Equatable, Identifiable {
    let version: String
    let headline: String
    let highlights: [Highlight]
    var id: String { version }

    struct Highlight: Equatable, Identifiable {
        let icon: String
        let title: String
        let body: String
        var id: String { title }
    }
}

enum WhatsNewRegistry {
    /// Releases ordered newest first. The runtime picks `releases.first`
    /// whose `version` matches the running bundle's `CFBundleShortVersionString`.
    static let releases: [WhatsNewRelease] = [
        WhatsNewRelease(
            version: "1.2.4",
            headline: "More private. Easier to start. Cleaner backups.",
            highlights: [
                .init(
                    icon: "faceid",
                    title: "App lock",
                    body: "Optional Face ID / Touch ID lock in Settings → Privacy. The app re-locks after 30 seconds in the background so an over-the-shoulder glance can't read your entries."
                ),
                .init(
                    icon: "checkmark.circle.fill",
                    title: "First-run setup",
                    body: "New users get a six-step onboarding that captures a baseline ASRM and PHQ-2 so the insight cards have something to anchor against."
                ),
                .init(
                    icon: "square.and.arrow.up.fill",
                    title: "Backups now include everything",
                    body: "Export / import preserves your onboarding choices, baseline survey scores, and any extra reminder times you've added. Older backup files still import."
                ),
            ]
        ),
        WhatsNewRelease(
            version: "1.2.3",
            headline: "Easier to read your patterns, easier to reach support.",
            highlights: [
                .init(
                    icon: "chart.bar.xaxis",
                    title: "Life Chart",
                    body: "A NIMH-style course-of-illness chart now lives in Insights → Open life chart. Bars rise above the line for activation, drop below for depression, with med-change and trigger markers on the zero line."
                ),
                .init(
                    icon: "phone.bubble.fill",
                    title: "Local crisis lines",
                    body: "Safety Plan now surfaces vetted crisis lines for your region — call, text, or open the web with one tap. International directory as a fallback."
                ),
                .init(
                    icon: "moon.stars.fill",
                    title: "Sleep + mixed-features fixes",
                    body: "Apple Health sleep no longer counts naps toward last night's total, and the \"Mixed features\" pill now follows DSM-5 markers instead of generic instability."
                ),
            ]
        ),
    ]

    static func release(for version: String) -> WhatsNewRelease? {
        releases.first { $0.version == version }
    }

    static func currentBundleVersion(bundle: Bundle = .main) -> String {
        (bundle.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "0"
    }
}
