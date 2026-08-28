#if os(macOS)
import XCTest
@testable import SFCallMac

final class SpeechAnalyzerRuntimeTests: XCTestCase {
    func testNativeRuntimeUsesIndependentSpeechAnalyzerTranscribers() async throws {
        let source = AudioProcessSource(
            id: 42,
            pid: 4_242,
            title: "Test Process",
            bundleID: "com.example.test",
            isRunningOutput: true
        )

        let runtime = try await LiveCallSessionRuntime.native(source: source)
        let remote = runtime.remoteSpeech as? SpeechAnalyzerTranscriber
        let microphone = runtime.microphoneSpeech as? SpeechAnalyzerTranscriber

        XCTAssertNotNil(remote)
        XCTAssertNotNil(microphone)
        if let remote, let microphone {
            XCTAssertFalse(remote === microphone)
        }
    }
}
#endif
