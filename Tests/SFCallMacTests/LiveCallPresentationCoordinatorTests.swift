#if os(macOS)
import XCTest
import SFCallCore
@testable import SFCallMac

final class LiveCallPresentationCoordinatorTests: XCTestCase {
    func testRemotePartialUpdatesHUDWithoutRequest() {
        let fixture = makeFixture()
        let coordinator = LiveCallPresentationCoordinator(
            baseline: fixture.baseline,
            clientFacts: fixture.clientFacts
        )

        let update = coordinator.ingestRemote(
            AppleSpeechTranscript(text: "Can we launch Friday?", isFinal: false)
        )

        XCTAssertEqual(update.hud.clientTranscript, "Can we launch Friday?")
        XCTAssertEqual(update.hud.sayThis, "")
        XCTAssertEqual(update.hud.vietnameseHint, "")
        XCTAssertNil(update.responseRequest)
    }

    func testRemoteFinalProducesResponseRequestAndThinkingHint() throws {
        let fixture = makeFixture()
        let coordinator = LiveCallPresentationCoordinator(
            baseline: fixture.baseline,
            clientFacts: fixture.clientFacts
        )

        let update = coordinator.ingestRemote(
            AppleSpeechTranscript(text: "Can we launch Friday?", isFinal: true)
        )

        let request = try XCTUnwrap(update.responseRequest)
        XCTAssertEqual(request.clientSaid, "Can we launch Friday?")
        XCTAssertEqual(request.baselineVersion, 3)
        XCTAssertEqual(request.confirmedRequirements, ["Launch after approval"])
        XCTAssertEqual(request.clientFacts, ["Prefers concise updates"])
        XCTAssertEqual(update.hud.clientTranscript, "Can we launch Friday?")
        XCTAssertEqual(update.hud.sayThis, "")
        XCTAssertEqual(update.hud.vietnameseHint, "Đang chuẩn bị câu trả lời…")
    }

    func testMicrophoneFinalNeverProducesResponseRequestOrOverwritesClientTranscript() {
        let fixture = makeFixture()
        let coordinator = LiveCallPresentationCoordinator(
            baseline: fixture.baseline,
            clientFacts: fixture.clientFacts
        )

        _ = coordinator.ingestRemote(
            AppleSpeechTranscript(text: "What is the timeline?", isFinal: false)
        )
        let update = coordinator.ingestMicrophone(
            AppleSpeechTranscript(text: "Let me check that.", isFinal: true)
        )

        XCTAssertNil(update.responseRequest)
        XCTAssertEqual(update.hud.clientTranscript, "What is the timeline?")
        XCTAssertEqual(update.hud.sayThis, "")
        XCTAssertEqual(update.hud.vietnameseHint, "")
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
#endif
