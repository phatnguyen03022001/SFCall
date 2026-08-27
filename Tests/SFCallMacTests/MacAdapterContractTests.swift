import XCTest
@testable import SFCallMac

final class MacAdapterContractTests: XCTestCase {
    func testPlatformSupportMatchesOperatingSystem() {
#if os(macOS)
        XCTAssertTrue(MacAdapterAvailability.isSupportedPlatform)
#else
        XCTAssertFalse(MacAdapterAvailability.isSupportedPlatform)
#endif
    }
}
