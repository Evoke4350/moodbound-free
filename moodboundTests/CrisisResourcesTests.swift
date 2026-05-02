import XCTest
@testable import moodbound

final class CrisisResourcesTests: XCTestCase {
    func testUSReturns988() {
        let resources = CrisisResources.forRegion("US")
        XCTAssertTrue(resources.contains { $0.phone == "988" })
    }

    func testGBReturnsSamaritans() {
        let resources = CrisisResources.forRegion("GB")
        XCTAssertTrue(resources.contains { $0.name.contains("Samaritans") && $0.phone == "116123" })
    }

    func testAustraliaReturnsLifeline() {
        let resources = CrisisResources.forRegion("AU")
        XCTAssertTrue(resources.contains { $0.name == "Lifeline" })
    }

    func testCaseInsensitiveRegionLookup() {
        XCTAssertEqual(
            CrisisResources.forRegion("us").map(\.id),
            CrisisResources.forRegion("US").map(\.id)
        )
    }

    func testUnknownRegionFallsBackToInternationalDirectory() {
        let resources = CrisisResources.forRegion("ZZ")
        XCTAssertEqual(resources.count, 1)
        XCTAssertEqual(resources.first?.regionCode, "INT")
        XCTAssertNotNil(resources.first?.web)
    }

    func testNilRegionFallsBack() {
        let resources = CrisisResources.forRegion(nil)
        XCTAssertEqual(resources.first?.regionCode, "INT")
    }

    func testEverySeededResourceHasReachableContactMethod() {
        // Each entry must surface at least one of phone / sms / web — an
        // entry with none of those is unusable in the UI.
        let regions = ["US", "CA", "GB", "IE", "AU", "NZ", "DE", "FR", "NL", "ES", "BR", "MX", "JP", "IN"]
        for region in regions {
            let resources = CrisisResources.forRegion(region)
            for resource in resources {
                let hasContact = !resource.phone.isEmpty || resource.sms != nil || resource.web != nil
                XCTAssertTrue(hasContact, "\(region) / \(resource.name) has no reachable contact method")
            }
        }
    }
}
