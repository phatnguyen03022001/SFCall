#if os(macOS)
import AVFoundation
import CoreMedia
import XCTest
import SFCallCore
@testable import SFCallMac

final class LiveCallHUDSessionTests: XCTestCase {
    @MainActor
    func testSuccessfulRuntimeShowsHUDRoutesRemoteTranscriptAndHidesOnStop() async throws {
        let fixture = makeFixture()
        let hud = FakeHUDPresenter()
        let remoteAudio = FakeHUDRemoteAudioSource()
        let microphoneAudio = FakeHUDMicrophoneAudioSource()
        let remoteSpeech = FakeHUDSpeechTranscriber()
        let microphoneSpeech = FakeHUDSpeechTranscriber()
        let runtime = LiveCallSessionRuntime(
            remoteAudio: remoteAudio,
            microphoneAudio: microphoneAudio,
            remoteSpeech: remoteSpeech,
            microphoneSpeech: microphoneSpeech
        )
        var startResult: Result<Void, Error>?
        var requests: [ResponseRequest] = []

        let session = LiveCallHUDSession(
            baseline: fixture.baseline,
            clientFacts: fixture.clientFacts,
            hud: hud,
            onResponseRequest: { requests.append($0) }
        )

        session.start(runtime: runtime) { startResult = $0 }

        XCTAssertNoThrow(try startResult?.get())
        XCTAssertEqual(hud.showCount, 1)

        remoteSpeech.emit(AppleSpeechTranscript(text: "Can we ship Friday?", isFinal: true))
        await Task.yield()

        XCTAssertEqual(hud.updates.last?.clientTranscript, "Can we ship Friday?")
        XCTAssertEqual(hud.updates.last?.vietnameseHint, "Đang chuẩn bị câu trả lời…")
        XCTAssertEqual(requests.map(\.clientSaid), ["Can we ship Friday?"])

        session.stop()
        XCTAssertEqual(hud.hideCount, 1)
    }

    @MainActor
    func testFailedRuntimeDoesNotShowHUDAndLeavesItHidden() {
        let fixture = makeFixture()
        let hud = FakeHUDPresenter()
        let runtime = LiveCallSessionRuntime(
            remoteAudio: FakeHUDRemoteAudioSource(),
            microphoneAudio: FakeHUDMicrophoneAudioSource(startError: HUDTestError.microphoneStart),
            remoteSpeech: FakeHUDSpeechTranscriber(),
            microphoneSpeech: FakeHUDSpeechTranscriber()
        )
        var result: Result<Void, Error>?

        let session = LiveCallHUDSession(
            baseline: fixture.baseline,
            clientFacts: fixture.clientFacts,
            hud: hud,
            onResponseRequest: { _ in }
        )

        session.start(runtime: runtime) { result = $0 }

        XCTAssertThrowsError(try result?.get())
        XCTAssertEqual(hud.showCount, 0)
        XCTAssertEqual(hud.hideCount, 1)
    }

    @MainActor
    func testNativeStartConvenienceSignatureExists() {
        let fixture = makeFixture()
        let session = LiveCallHUDSession(
            baseline: fixture.baseline,
            clientFacts: fixture.clientFacts,
            hud: FakeHUDPresenter(),
            onResponseRequest: { _ in }
        )

        let start: (
            CallCaptureSource,
            String,
            @escaping (Result<Void, Error>) -> Void
        ) -> Void = session.start(source:localeIdentifier:completion:)

        _ = start
    }

    private func makeFixture() -> (baseline: CaseBaseline, clientFacts: [ClientFactRecord]) {
        let clientID = UUID()
        let caseID = UUID()
        let requirement = RequirementRecord(
            caseID: caseID,
            owner: .mutual,
            text: "Launch after approval",
            status: .confirmed,
            evidenceRefs: ["contract:1"]
        )
        let fact = ClientFactRecord(
            clientID: clientID,
            kind: .preference,
            value: "Prefers concise updates",
            evidenceRefs: ["message:1"]
        )
        return (
            CaseBaseline(version: 3, requirements: [requirement]),
            [fact]
        )
    }
}

private enum HUDTestError: Error {
    case microphoneStart
}

@MainActor
private final class FakeHUDPresenter: LiveCallHUDPresenting {
    private(set) var showCount = 0
    private(set) var hideCount = 0
    private(set) var updates: [PrivateHUDContent] = []

    func show() {
        showCount += 1
    }

    func hide() {
        hideCount += 1
    }

    func update(_ content: PrivateHUDContent) {
        updates.append(content)
    }
}

private final class FakeHUDRemoteAudioSource: LiveCallRemoteAudioSource, @unchecked Sendable {
    func start(
        onAudio: @escaping @Sendable (CMSampleBuffer) -> Void,
        completion: @escaping @Sendable (Error?) -> Void
    ) {
        completion(nil)
    }

    func stop(completion: (@Sendable () -> Void)?) {
        completion?()
    }
}

private final class FakeHUDMicrophoneAudioSource: LiveCallMicrophoneAudioSource {
    private let startError: Error?

    init(startError: Error? = nil) {
        self.startError = startError
    }

    func start(onBuffer: @escaping (AVAudioPCMBuffer) -> Void) throws {
        if let startError { throw startError }
    }

    func stop() {}
}

private final class FakeHUDSpeechTranscriber: LiveCallSpeechTranscribing {
    private var onTranscript: ((AppleSpeechTranscript) -> Void)?

    func start(onTranscript: @escaping (AppleSpeechTranscript) -> Void) throws {
        self.onTranscript = onTranscript
    }

    func append(sampleBuffer: CMSampleBuffer) {}
    func append(pcmBuffer: AVAudioPCMBuffer) {}

    func stop() {
        onTranscript = nil
    }

    func emit(_ transcript: AppleSpeechTranscript) {
        onTranscript?(transcript)
    }
}
#endif
