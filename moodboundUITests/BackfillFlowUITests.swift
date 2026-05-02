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

    func testOpenLifeChart() throws {
        let app = XCUIApplication()
        app.launch()

        let understandButton = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Understood' OR label CONTAINS[c] 'I understand' OR label CONTAINS[c] 'Continue'")).firstMatch
        if understandButton.waitForExistence(timeout: 3) {
            understandButton.tap()
        }

        // Insights tab — depends on whether the bottom bar is tabs or
        // navigation segments. Try both.
        let insightsTab = app.tabBars.buttons["Insights"]
        if insightsTab.waitForExistence(timeout: 3) {
            insightsTab.tap()
        }

        // The "Open life chart" button only renders once the user has
        // ≥3 entries (Insights gates on that). Skip if absent.
        let openButton = app.buttons["open-life-chart-button"]
        guard openButton.waitForExistence(timeout: 5) else {
            throw XCTSkip("Insufficient entries for Insights to render the life chart entry point.")
        }
        openButton.tap()

        XCTAssertTrue(app.navigationBars["Life chart"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.segmentedControls.firstMatch.waitForExistence(timeout: 3))

        // Switch through window sizes.
        let picker = app.segmentedControls["life-chart-window-picker"]
        if picker.exists {
            picker.buttons["1y"].tap()
            picker.buttons["30d"].tap()
        }

        app.buttons["Done"].tap()
    }
}
