import XCTest
@testable import SFCallCore

final class LiveCallRoutingTests: XCTestCase {
    func testRemoteTranscriptIsClientAndFinalTurnBuildsRequest() {
        let caseID = UUID()
        let requirement = RequirementRecord(
            caseID: caseID,
            owner: .mutual,
            text: "Google login",
            status: .confirmed,
            evidenceRefs: ["E-1"]
        )
        let baseline = CaseBaseline(version: 2, requirements: [requirement])
        let client = ClientRecord(displayName: "Client")
        let facts = [ClientFactRecord(
            clientID: client.id,
            kind: .priority,
            value: "Launch quickly",
            evidenceRefs: ["E-2"]
        )]
        let router = LiveCallRouter(maxRecentTurns: 4)

        XCTAssertNil(router.ingestRemote(text: "Can we add", isFinal: false, baseline: baseline, clientFacts: facts))
        let request = router.ingestRemote(text: "Can we add Apple login too?", isFinal: true, baseline: baseline, clientFacts: facts)

        XCTAssertEqual(request?.clientSaid, "Can we add Apple login too?")
        XCTAssertEqual(request?.recentTurns.last?.speaker, .client)
        XCTAssertEqual(request?.baselineVersion, 2)
    }

    func testMicrophoneTranscriptIsUserAndNeverTriggersResponseRequest() {
        let baseline = CaseBaseline(version: 0, requirements: [])
        let router = LiveCallRouter(maxRecentTurns: 4)

        let request = router.ingestMicrophone(
            text: "Let me check that.",
            isFinal: true,
            baseline: baseline,
            clientFacts: []
        )

        XCTAssertNil(request)
        XCTAssertEqual(router.recentTurns, [ConversationTurn(speaker: .user, text: "Let me check that.")])
    }
}
