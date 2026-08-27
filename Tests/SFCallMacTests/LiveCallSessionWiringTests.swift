#if os(macOS)
import AVFoundation
import CoreMedia
import XCTest
import SFCallCore
@testable import SFCallMac

final class LiveCallSessionWiringTests: XCTestCase {
    func testRuntimeRoutesBothSpeechStreamsAndStopsAllComponents() throws {
        let fixture = makeFixture()
        let remoteAudio = FakeRemoteAudioSource()
        let microphoneAudio = FakeMicrophoneAudioSource()
        let remoteSpeech = FakeSpeechTranscriber()
        let microphoneSpeech = FakeSpeechTranscriber()
        var hudUpdates: [PrivateHUDContent] = []
        var requests: [ResponseRequest] = []
        var startResult: Result<Void, Error>?

        let controller = LiveCallSessionController(
            baseline: fixture.baseline,
            clientFacts: fixture.clientFacts,
            onHUDUpdate: { hudUpdates.append($0) },
            onResponseRequest: { requests.append($0) }
        )
        let runtime = LiveCallSessionRuntime(
            remoteAudio: remoteAudio,
            microphoneAudio: microphoneAudio,
            remoteSpeech: remoteSpeech,
            microphoneSpeech: microphoneSpeech
        )

        controller.start(runtime: runtime) { startResult = $0 }

        XCTAssertNoThrow(try startResult?.get())
        XCTAssertEqual(remoteAudio.startCount, 1)
        XCTAssertEqual(microphoneAudio.startCount, 1)
        XCTAssertEqual(remoteSpeech.startCount, 1)
        XCTAssertEqual(microphoneSpeech.startCount, 1)

        remoteSpeech.emit(AppleSpeechTranscript(text: "Can we ship Friday?", isFinal: true))
        microphoneSpeech.emit(AppleSpeechTranscript(text: "Let me check.", isFinal: true))

        XCTAssertEqual(requests.map(\.clientSaid), ["Can we ship Friday?"])
        XCTAssertEqual(hudUpdates.last?.clientTranscript, "Can we ship Friday?")

        controller.stop()

        XCTAssertEqual(remoteAudio.stopCount, 1)
        XCTAssertEqual(microphoneAudio.stopCount, 1)
        XCTAssertEqual(remoteSpeech.stopCount, 1)
        XCTAssertEqual(microphoneSpeech.stopCount, 1)
    }

    func testMicrophoneStartFailureCleansUpSpeechAndDoesNotStartRemoteAudio() {
        let fixture = makeFixture()
        let remoteAudio = FakeRemoteAudioSource()
        let microphoneAudio = FakeMicrophoneAudioSource(startError: TestError.microphoneStart)
        let remoteSpeech = FakeSpeechTranscriber()
        let microphoneSpeech = FakeSpeechTranscriber()
        var result: Result<Void, Error>?

        let controller = LiveCallSessionController(
            baseline: fixture.baseline,
            clientFacts: fixture.clientFacts,
            onHUDUpdate: { _ in },
            onResponseRequest: { _ in }
        )
        let runtime = LiveCallSessionRuntime(
            remoteAudio: remoteAudio,
            microphoneAudio: microphoneAudio,
            remoteSpeech: remoteSpeech,
            microphoneSpeech: microphoneSpeech
        )

        controller.start(runtime: runtime) { result = $0 }

        XCTAssertThrowsError(try result?.get())
        XCTAssertEqual(remoteAudio.startCount, 0)
        XCTAssertEqual(microphoneAudio.startCount, 1)
        XCTAssertEqual(remoteSpeech.stopCount, 1)
        XCTAssertEqual(microphoneSpeech.stopCount, 1)
        XCTAssertEqual(microphoneAudio.stopCount, 1)
    }

    func testRemoteAudioStartFailureCleansUpEntireRuntime() {
        let fixture = makeFixture()
        let remoteAudio = FakeRemoteAudioSource(startError: TestError.remoteStart)
        let microphoneAudio = FakeMicrophoneAudioSource()
        let remoteSpeech = FakeSpeechTranscriber()
        let microphoneSpeech = FakeSpeechTranscriber()
        var result: Result<Void, Error>?

        let controller = LiveCallSessionController(
            baseline: fixture.baseline,
            clientFacts: fixture.clientFacts,
            onHUDUpdate: { _ in },
            onResponseRequest: { _ in }
        )
        let runtime = LiveCallSessionRuntime(
            remoteAudio: remoteAudio,
            microphoneAudio: microphoneAudio,
            remoteSpeech: remoteSpeech,
            microphoneSpeech: microphoneSpeech
        )

        controller.start(runtime: runtime) { result = $0 }

        XCTAssertThrowsError(try result?.get())
        XCTAssertEqual(remoteAudio.startCount, 1)
        XCTAssertEqual(remoteAudio.stopCount, 1)
        XCTAssertEqual(microphoneAudio.stopCount, 1)
        XCTAssertEqual(remoteSpeech.stopCount, 1)
        XCTAssertEqual(microphoneSpeech.stopCount, 1)
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

private enum TestError: Error {
    case microphoneStart
    case remoteStart
}

private final class FakeRemoteAudioSource: LiveCallRemoteAudioSource, @unchecked Sendable {
    private let startError: Error?
    private(set) var startCount = 0
    private(set) var stopCount = 0

    init(startError: Error? = nil) {
        self.startError = startError
    }

    func start(
        onAudio: @escaping @Sendable (CMSampleBuffer) -> Void,
        completion: @escaping @Sendable (Error?) -> Void
    ) {
        startCount += 1
        completion(startError)
    }

    func stop(completion: (@Sendable () -> Void)?) {
        stopCount += 1
        completion?()
    }
}

private final class FakeMicrophoneAudioSource: LiveCallMicrophoneAudioSource {
    private let startError: Error?
    private(set) var startCount = 0
    private(set) var stopCount = 0

    init(startError: Error? = nil) {
        self.startError = startError
    }

    func start(onBuffer: @escaping (AVAudioPCMBuffer) -> Void) throws {
        startCount += 1
        if let startError { throw startError }
    }

    func stop() {
        stopCount += 1
    }
}

private final class FakeSpeechTranscriber: LiveCallSpeechTranscribing {
    private var onTranscript: ((AppleSpeechTranscript) -> Void)?
    private(set) var startCount = 0
    private(set) var stopCount = 0

    func start(onTranscript: @escaping (AppleSpeechTranscript) -> Void) throws {
        startCount += 1
        self.onTranscript = onTranscript
    }

    func append(sampleBuffer: CMSampleBuffer) {}
    func append(pcmBuffer: AVAudioPCMBuffer) {}

    func stop() {
        stopCount += 1
        onTranscript = nil
    }

    func emit(_ transcript: AppleSpeechTranscript) {
        onTranscript?(transcript)
    }
}
#endif
