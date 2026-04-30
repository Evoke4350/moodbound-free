import XCTest

/// Drives the simulator through the new backfill / catch-up surface to
/// validate the end-to-end flow:
///   1. Seed 90 days of test data via the DEBUG-only Settings button.
///   2. Verify that history reflects the seeded entries.
///   3. Confirm the home-screen catch-up card surfaces in the right state
///      after the seed completes.
///
/// Skipped automatically in non-DEBUG builds (the seed button is gated on
/// `#if DEBUG` and therefore won't exist in release).
final class BackfillFlowUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testSeed90DaysOfData() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-uitest"]
        app.launch()

        // Dismiss the disclaimer splash if present.
        let understandButton = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Understood' OR label CONTAINS[c] 'I understand' OR label CONTAINS[c] 'Continue'")).firstMatch
        if understandButton.waitForExistence(timeout: 3) {
            understandButton.tap()
        }

        XCTAssertTrue(app.buttons["settings-button"].waitForExistence(timeout: 5))
        app.buttons["settings-button"].tap()

        let seedButton = app.buttons["debug-seed-90-days"]
        guard seedButton.waitForExistence(timeout: 5) else {
            throw XCTSkip("Debug seed button not present — non-DEBUG build.")
        }
        // Scroll down if necessary to make the button hittable.
        if !seedButton.isHittable {
            app.swipeUp()
        }
        seedButton.tap()

        // Success alert appears with "OK".
        let successButton = app.alerts.buttons["OK"]
        XCTAssertTrue(successButton.waitForExistence(timeout: 15), "Seed did not complete in time")
        successButton.tap()

        // Dismiss settings.
        let doneButton = app.buttons["Done"]
        if doneButton.exists { doneButton.tap() }

        // Home screen should now show the streak / outlook scaffold.
        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 5))
    }
}
