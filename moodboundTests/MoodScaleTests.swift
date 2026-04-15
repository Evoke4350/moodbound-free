import XCTest
@testable import moodbound

final class MoodScaleTests: XCTestCase {

    func testAllCasesCount() {
        XCTAssertEqual(MoodScale.allCases.count, 7)
    }

    func testRawValues() {
        XCTAssertEqual(MoodScale.severeDepression.rawValue, -3)
        XCTAssertEqual(MoodScale.balanced.rawValue, 0)
        XCTAssertEqual(MoodScale.mania.rawValue, 3)
    }

    func testLabelsNotEmpty() {
        for scale in MoodScale.allCases {
            XCTAssertFalse(scale.label.isEmpty, "\(scale) has empty label")
            XCTAssertFalse(scale.shortLabel.isEmpty, "\(scale) has empty shortLabel")
            XCTAssertFalse(scale.emoji.isEmpty, "\(scale) has empty emoji")
        }
    }

    func testSpecificLabels() {
        XCTAssertEqual(MoodScale.severeDepression.label, "Severe Depression")
        XCTAssertEqual(MoodScale.balanced.label, "Balanced")
        XCTAssertEqual(MoodScale.mania.label, "Mania")
    }

    func testIdMatchesRawValue() {
        for scale in MoodScale.allCases {
            XCTAssertEqual(scale.id, scale.rawValue)
        }
    }

    func testRoundTrip() {
        for raw in -3...3 {
            let scale = MoodScale(rawValue: raw)
            XCTAssertNotNil(scale, "No case for rawValue \(raw)")
            XCTAssertEqual(scale?.rawValue, raw)
        }
    }

    func testInvalidRawValue() {
        XCTAssertNil(MoodScale(rawValue: -4))
        XCTAssertNil(MoodScale(rawValue: 4))
    }
}
