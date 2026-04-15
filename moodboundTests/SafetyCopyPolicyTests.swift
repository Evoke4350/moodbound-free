import XCTest
@testable import moodbound

final class SafetyCopyPolicyTests: XCTestCase {
    func testSanitizeReplacesProhibitedPhrase() {
        let input = ["You are definitely in crisis."]
        let output = SafetyCopyPolicy.sanitize(input)
        XCTAssertEqual(output.count, 1)
        XCTAssertFalse(output[0].lowercased().contains("definitely"))
    }

    func testCrisisBannerTextExistsForCritical() {
        let text = SafetyCopyPolicy.crisisBannerText(for: .critical)
        XCTAssertNotNil(text)
    }

    // MARK: - Build 7 copy tone regressions

    /// Build 7 rewrote the critical crisis banner to be supportive rather
    /// than directive. This test locks in the key tone markers: the string
    /// must contain "you don't have to face this alone" (the supportive
    /// hook) and must NOT contain the old directive phrasing
    /// ("immediately").
    func testCriticalCrisisCopyIsSupportive() {
        let text = SafetyCopyPolicy.crisisBannerText(for: .critical) ?? ""
        XCTAssertTrue(
            text.lowercased().contains("you don't have to face this alone")
                || text.lowercased().contains("don't have to face"),
            "Critical crisis copy lost its supportive hook: \(text)"
        )
        XCTAssertFalse(
            text.lowercased().contains("immediately"),
            "Critical crisis copy regressed to directive language: \(text)"
        )
    }

    /// High-severity banner should invite action, not issue orders.
    func testHighSeverityCopyInvitesActionWithoutPressure() {
        let text = SafetyCopyPolicy.crisisBannerText(for: .high) ?? ""
        XCTAssertTrue(
            text.lowercased().contains("care team") || text.lowercased().contains("trusted person"),
            "High-severity copy dropped its care-team / trusted-person language: \(text)"
        )
        // Old directive "contact ... today" is fine; the regression we're
        // guarding against is the "symptoms escalating" clinical phrasing.
        XCTAssertFalse(
            text.lowercased().contains("symptoms are escalating"),
            "High-severity copy regressed to clinical phrasing: \(text)"
        )
    }

    /// The sanitized fallback is the worst-case string the engine will
    /// ever show, so it must stay warm.
    func testSanitizedFallbackIsWarm() {
        // Trigger the fallback by passing a prohibited fragment.
        let fallback = SafetyCopyPolicy.sanitizeMessage("it's nothing to worry about")
        XCTAssertFalse(
            fallback.lowercased().contains("patterns were detected"),
            "Fallback regressed to old bureaucratic phrasing: \(fallback)"
        )
        XCTAssertTrue(
            fallback.lowercased().contains("safety plan"),
            "Fallback should still point at the safety plan: \(fallback)"
        )
    }
}
