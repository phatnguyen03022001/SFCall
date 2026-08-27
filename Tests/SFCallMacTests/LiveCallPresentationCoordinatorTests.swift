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
        XCTAssertEqual(update.hud.analysisState, .idle)
        XCTAssertNil(update.responseRequest)
    }

    func testRemoteFinalProducesResponseRequestAndAnalyzingState() throws {
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
        XCTAssertEqual(update.hud.analysisState, .analyzing)
        XCTAssertEqual(update.hud.sayThis, "")
    }

    func testApplyingAdviceFillsVietnameseRiskMoveAndReply() {
        let fixture = makeFixture()
        let coordinator = LiveCallPresentationCoordinator(
            baseline: fixture.baseline,
            clientFacts: fixture.clientFacts
        )
        _ = coordinator.ingestRemote(
            AppleSpeechTranscript(text: "Commit to Friday now.", isFinal: true)
        )

        let hud = coordinator.applyNegotiationAdvice(makeAdvice())

        XCTAssertEqual(hud.clientTranslationVietnamese, "Hãy cam kết giao vào thứ Sáu ngay.")
        XCTAssertEqual(hud.riskLevel, .high)
        XCTAssertTrue(hud.trapDetected)
        XCTAssertEqual(hud.confidencePercent, 91)
        XCTAssertEqual(hud.riskReasonVietnamese, "Họ đang yêu cầu cam kết trước khi chốt phạm vi.")
        XCTAssertEqual(hud.recommendedMoveVietnamese, "Chốt phạm vi trước khi xác nhận thời hạn.")
        XCTAssertEqual(hud.sayThis, "Let me confirm the scope first. Then I can confirm the timeline.")
        XCTAssertEqual(hud.vietnameseHint, "Để tôi xác nhận phạm vi trước. Sau đó tôi có thể xác nhận tiến độ.")
        XCTAssertEqual(hud.analysisState, .ready)
    }

    func testMicrophoneTurnDoesNotClearCurrentAdvice() {
        let fixture = makeFixture()
        let coordinator = LiveCallPresentationCoordinator(
            baseline: fixture.baseline,
            clientFacts: fixture.clientFacts
        )
        _ = coordinator.ingestRemote(
            AppleSpeechTranscript(text: "Commit to Friday now.", isFinal: true)
        )
        _ = coordinator.applyNegotiationAdvice(makeAdvice())

        let update = coordinator.ingestMicrophone(
            AppleSpeechTranscript(text: "Let me confirm the scope first.", isFinal: true)
        )

        XCTAssertNil(update.responseRequest)
        XCTAssertEqual(update.hud.clientTranscript, "Commit to Friday now.")
        XCTAssertEqual(update.hud.analysisState, .ready)
        XCTAssertEqual(update.hud.sayThis, "Let me confirm the scope first. Then I can confirm the timeline.")
    }

    func testAdviceFailureDoesNotLoseClientTranscript() {
        let fixture = makeFixture()
        let coordinator = LiveCallPresentationCoordinator(
            baseline: fixture.baseline,
            clientFacts: fixture.clientFacts
        )
        _ = coordinator.ingestRemote(
            AppleSpeechTranscript(text: "What is your final price?", isFinal: true)
        )

        let hud = coordinator.applyNegotiationFailure("Apple Intelligence is unavailable.")

        XCTAssertEqual(hud.clientTranscript, "What is your final price?")
        XCTAssertEqual(hud.analysisState, .unavailable("Apple Intelligence is unavailable."))
    }

    private func makeAdvice() -> NegotiationAdvice {
        NegotiationAdvice(
            translatedClientTextVietnamese: "Hãy cam kết giao vào thứ Sáu ngay.",
            trapDetected: true,
            riskLevel: .high,
            riskReasonVietnamese: "Họ đang yêu cầu cam kết trước khi chốt phạm vi.",
            recommendedMoveVietnamese: "Chốt phạm vi trước khi xác nhận thời hạn.",
            replyEnglish: "Let me confirm the scope first. Then I can confirm the timeline.",
            replyVietnamese: "Để tôi xác nhận phạm vi trước. Sau đó tôi có thể xác nhận tiến độ.",
            confidencePercent: 91
        )
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
