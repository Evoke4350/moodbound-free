import XCTest
@testable import moodbound

final class WhatsNewRegistryTests: XCTestCase {
    func testReleasesAreUniqueByVersion() {
        let versions = WhatsNewRegistry.releases.map(\.version)
        XCTAssertEqual(versions.count, Set(versions).count, "Duplicate release versions in WhatsNewRegistry")
    }

    func testEveryReleaseHasAtLeastOneHighlight() {
        for release in WhatsNewRegistry.releases {
            XCTAssertFalse(release.highlights.isEmpty, "\(release.version) has no highlights")
        }
    }

    func testCurrentVersionHasAReleaseEntry() {
        let current = WhatsNewRegistry.currentBundleVersion()
        XCTAssertNotNil(
            WhatsNewRegistry.release(for: current),
            "Bundle version \(current) needs a WhatsNewRegistry entry — add highlights or remove this assertion when intentionally skipping a version."
        )
    }

    func testUnknownVersionReturnsNil() {
        XCTAssertNil(WhatsNewRegistry.release(for: "0.0.0"))
    }

    func testHighlightFieldsArePresent() {
        for release in WhatsNewRegistry.releases {
            for highlight in release.highlights {
                XCTAssertFalse(highlight.icon.isEmpty)
                XCTAssertFalse(highlight.title.isEmpty)
                XCTAssertFalse(highlight.body.isEmpty)
            }
        }
    }
}
