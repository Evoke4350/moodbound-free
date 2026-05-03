import XCTest

/// Drives the simulator through the new install-time onboarding flow:
/// welcome → diagnosis → ASRM → PHQ-2 → reminder → permissions → done.
/// Uses the `-uitest-reset-onboarding` launch arg (handled by the app)
/// so the flow appears even if a prior test run already completed it.
final class OnboardingFlowUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testWalkOnboardingHappyPath() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-uitest", "-uitest-reset-onboarding"]
        app.launch()

        // Disclaimer → onboarding sheet.
        let nextButton = app.buttons["onboarding-next"]
        XCTAssertTrue(nextButton.waitForExistence(timeout: 8), "Onboarding did not appear")

        // Welcome → "Get started"
        nextButton.tap()

        // Diagnosis: pick "Bipolar II"
        XCTAssertTrue(app.buttons["diagnosis-bipolarII"].waitForExistence(timeout: 3))
        app.buttons["diagnosis-bipolarII"].tap()
        nextButton.tap()

        // ASRM: pick option 1 for each of 5 questions if visible; otherwise skip.
        for index in 1...5 {
            let id = "asrm-\(index)-\(["cheerfulness", "confidence", "sleep", "speech", "activity"][index - 1])-answer-1"
            let answer = app.buttons[id]
            if answer.waitForExistence(timeout: 2) {
                if !answer.isHittable { app.swipeUp() }
                answer.tap()
            }
        }
        nextButton.tap()

        // PHQ-2: pick option 1 for both questions
        for id in ["phq2-1-interest-answer-1", "phq2-2-down-answer-1"] {
            let answer = app.buttons[id]
            if answer.waitForExistence(timeout: 2) {
                if !answer.isHittable { app.swipeUp() }
                answer.tap()
            }
        }
        nextButton.tap()

        // Reminder: leave default (off) — just continue.
        nextButton.tap()

        // Permissions: skip.
        if app.buttons["onboarding-skip"].exists {
            app.buttons["onboarding-skip"].tap()
        } else {
            nextButton.tap()
        }

        // Done screen → finish.
        XCTAssertTrue(nextButton.waitForExistence(timeout: 5))
        nextButton.tap()

        // Land on Today.
        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 8))
    }
}
