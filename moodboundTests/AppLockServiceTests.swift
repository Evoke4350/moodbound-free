import XCTest
import LocalAuthentication
@testable import moodbound

/// `AppLockService` is mostly a thin wrapper around LAContext. The
/// only deterministic behavior we can test without a device is the
/// capability mapping from LAContext.biometryType to our enum, and the
/// outcome shape when the context refuses to evaluate.
final class AppLockServiceTests: XCTestCase {
    func testCapabilityReturnsUnavailableWhenContextRefuses() {
        // Make a context that errors out of canEvaluatePolicy. The
        // simplest reliable way: invalidate it before asking. An
        // invalidated context returns false from canEvaluatePolicy.
        let context = LAContext()
        context.invalidate()
        XCTAssertEqual(AppLockService.capability(context: context), .unavailable)
    }

    func testAuthenticateReportsUnavailableWhenContextRefuses() async {
        let context = LAContext()
        context.invalidate()
        let outcome = await AppLockService.authenticate(contextFactory: { context })
        XCTAssertEqual(outcome, .unavailable)
    }

    func testBackgroundGraceIsConservative() {
        // 30 seconds is the documented sweet spot — long enough that
        // Control Center / notification-pull doesn't re-prompt, short
        // enough that walking away from the device requires re-auth.
        XCTAssertEqual(AppLockSettings.backgroundGraceSeconds, 30)
    }
}
