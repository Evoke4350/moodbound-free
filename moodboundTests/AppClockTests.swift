import XCTest
@testable import moodbound

final class AppClockTests: XCTestCase {
    override func setUp() {
        super.setUp()
        AppClock.reset()
    }

    override func tearDown() {
        AppClock.reset()
        super.tearDown()
    }

    func testSetAndResetTimeTravel() {
#if DEBUG
        XCTAssertFalse(AppClock.isTimeTraveling)

        let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)
        AppClock.set(fixedDate)

        XCTAssertTrue(AppClock.isTimeTraveling)
        XCTAssertEqual(AppClock.now.timeIntervalSince1970, fixedDate.timeIntervalSince1970, accuracy: 0.001)

        AppClock.reset()
        XCTAssertFalse(AppClock.isTimeTraveling)
#else
        XCTAssertFalse(AppClock.isTimeTraveling)
#endif
    }
}
