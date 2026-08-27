#if os(macOS)
import AVFoundation
import XCTest
import SFCallCore
@testable import SFCallMac

final class LiveCallHUDSessionTests: XCTestCase {
    @MainActor
    func testSuccessfulRuntimeShowsHUDRoutesTranscriptEventsAndAdvice() async throws {
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
        var speakers: [TranscriptSpeaker] = []
        var texts: [String] = []
        var finals: [Bool] = []

        let session = LiveCallHUDSession(
            baseline: fixture.baseline,
            clientFacts: fixture.clientFacts,
            hud: hud,
            onResponseRequest: { requests.append($0) },
            onTranscriptTurn: { speaker, text, isFinal in
                speakers.append(speaker)
                texts.append(text)
                finals.append(isFinal)
            }
        )

        session.start(runtime: runtime) { startResult = $0 }

        XCTAssertNoThrow(try startResult?.get())
        XCTAssertEqual(hud.showCount, 1)

        remoteSpeech.emit(AppleSpeechTranscript(text: "Can we ship Friday?", isFinal: true))
        microphoneSpeech.emit(AppleSpeechTranscript(text: "Let me check.", isFinal: true))
        await Task.yield()

        XCTAssertEqual(hud.updates.last?.clientTranscript, "Can we ship Friday?")
        XCTAssertEqual(hud.updates.last?.analysisState, .analyzing)
        XCTAssertEqual(requests.map(\.clientSaid), ["Can we ship Friday?"])
        XCTAssertEqual(speakers, [.client, .user])
        XCTAssertEqual(texts, ["Can we ship Friday?", "Let me check."])
        XCTAssertEqual(finals, [true, true])

        session.applyNegotiationAdvice(
            NegotiationAdvice(
                translatedClientTextVietnamese: "Chúng ta có thể giao vào thứ Sáu không?",
                trapDetected: false,
                riskLevel: .medium,
                riskReasonVietnamese: "Cần xác nhận phạm vi trước.",
                recommendedMoveVietnamese: "Làm rõ phạm vi.",
                replyEnglish: "Let me confirm the scope first.",
                replyVietnamese: "Để tôi xác nhận phạm vi trước.",
                confidencePercent: 80
            )
        )
        XCTAssertEqual(hud.updates.last?.analysisState, .ready)
        XCTAssertEqual(hud.updates.last?.sayThis, "Let me confirm the scope first.")

        session.stop()
        XCTAssertEqual(hud.hideCount, 1)
    }

    @MainActor
    func testAdviceFailureUpdatesHUDWithoutStoppingSession() {
        let fixture = makeFixture()
        let hud = FakeHUDPresenter()
        let session = LiveCallHUDSession(
            baseline: fixture.baseline,
            clientFacts: fixture.clientFacts,
            hud: hud,
            onResponseRequest: { _ in },
            onTranscriptTurn: { _, _, _ in }
        )

        session.applyNegotiationFailure("Apple Intelligence is unavailable.")

        XCTAssertEqual(hud.updates.last?.analysisState, .unavailable("Apple Intelligence is unavailable."))
        XCTAssertEqual(hud.hideCount, 0)
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
            onResponseRequest: { _ in },
            onTranscriptTurn: { _, _, _ in }
        )

        session.start(runtime: runtime) { result = $0 }

        XCTAssertThrowsError(try result?.get())
        XCTAssertEqual(hud.showCount, 0)
        XCTAssertEqual(hud.hideCount, 1)
    }

    @MainActor
    func testNativeStartConvenienceUsesAudioProcessSource() {
        let fixture = makeFixture()
        let session = LiveCallHUDSession(
            baseline: fixture.baseline,
            clientFacts: fixture.clientFacts,
            hud: FakeHUDPresenter(),
            onResponseRequest: { _ in },
            onTranscriptTurn: { _, _, _ in }
        )

        let start: (
            AudioProcessSource,
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
        return (CaseBaseline(version: 3, requirements: [requirement]), [fact])
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

    func show() { showCount += 1 }
    func hide() { hideCount += 1 }
    func update(_ content: PrivateHUDContent) { updates.append(content) }
}

private final class FakeHUDRemoteAudioSource: LiveCallRemoteAudioSource, @unchecked Sendable {
    func start(
        onAudio: @escaping (AVAudioPCMBuffer) -> Void,
        completion: @escaping @Sendable (Error?) -> Void
    ) {
        completion(nil)
    }

    func stop(completion: (@Sendable () -> Void)?) { completion?() }
}

private final class FakeHUDMicrophoneAudioSource: LiveCallMicrophoneAudioSource {
    private let startError: Error?
    init(startError: Error? = nil) { self.startError = startError }
    func start(onBuffer: @escaping (AVAudioPCMBuffer) -> Void) throws {
        if let startError { throw startError }
    }
    func stop() {}
}

private final class FakeHUDSpeechTranscriber: LiveCallSpeechTranscribing {
    private var onTranscript: ((AppleSpeechTranscript) -> Void)?
    func start(onTranscript: @escaping (AppleSpeechTranscript) -> Void) throws { self.onTranscript = onTranscript }
    func append(pcmBuffer: AVAudioPCMBuffer) {}
    func stop() { onTranscript = nil }
    func emit(_ transcript: AppleSpeechTranscript) { onTranscript?(transcript) }
}
#endif
