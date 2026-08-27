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

    func testScreenAudioCaptureIsSendable() {
#if os(macOS)
        requireSendable(ScreenAudioCapture.self)
#endif
    }

    private func requireSendable<T: Sendable>(_: T.Type) {}
}
