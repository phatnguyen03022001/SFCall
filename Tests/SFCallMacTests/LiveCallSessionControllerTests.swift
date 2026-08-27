#if os(macOS)
import XCTest
import SFCallCore
@testable import SFCallMac

final class LiveCallSessionControllerTests: XCTestCase {
    func testRemoteFinalPublishesHUDResponseAndTranscriptEvent() throws {
        let fixture = makeFixture()
        var hudUpdates: [PrivateHUDContent] = []
        var requests: [ResponseRequest] = []
        var speakers: [TranscriptSpeaker] = []
        let controller = LiveCallSessionController(
            baseline: fixture.baseline,
            clientFacts: fixture.clientFacts,
            onHUDUpdate: { hudUpdates.append($0) },
            onResponseRequest: { requests.append($0) },
            onTranscriptTurn: { speaker, _, _ in speakers.append(speaker) }
        )

        controller.ingestRemoteTranscript(
            AppleSpeechTranscript(text: "Can we ship Friday?", isFinal: true)
        )

        XCTAssertEqual(hudUpdates.last?.clientTranscript, "Can we ship Friday?")
        XCTAssertEqual(hudUpdates.last?.analysisState, .analyzing)
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests.first?.clientSaid, "Can we ship Friday?")
        XCTAssertEqual(speakers, [.client])
    }

    func testMicrophoneFinalPublishesHUDWithoutResponseAndPreservesClientText() {
        let fixture = makeFixture()
        var hudUpdates: [PrivateHUDContent] = []
        var requests: [ResponseRequest] = []
        let controller = LiveCallSessionController(
            baseline: fixture.baseline,
            clientFacts: fixture.clientFacts,
            onHUDUpdate: { hudUpdates.append($0) },
            onResponseRequest: { requests.append($0) }
        )

        controller.ingestRemoteTranscript(
            AppleSpeechTranscript(text: "What is the timeline?", isFinal: false)
        )
        controller.ingestMicrophoneTranscript(
            AppleSpeechTranscript(text: "Let me check.", isFinal: true)
        )

        XCTAssertEqual(hudUpdates.last?.clientTranscript, "What is the timeline?")
        XCTAssertEqual(hudUpdates.last?.analysisState, .idle)
        XCTAssertTrue(requests.isEmpty)
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
#endif
