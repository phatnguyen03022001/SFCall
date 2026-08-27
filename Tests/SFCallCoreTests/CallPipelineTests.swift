import XCTest
@testable import SFCallCore

final class CallPipelineTests: XCTestCase {
    func testFinalClientTurnBuildsResponseRequestFromStructuredContext() throws {
        let coordinator = CallTurnCoordinator(maxRecentTurns: 4)
        let baseline = CaseBaseline(
            version: 2,
            requirements: [
                RequirementRecord(
                    caseID: UUID(),
                    owner: .mutual,
                    text: "Email/password login",
                    status: .confirmed,
                    evidenceRefs: ["E-1"]
                )
            ]
        )
        let facts = [
            ClientFactRecord(
                clientID: UUID(),
                kind: .priority,
                value: "Launch this week",
                evidenceRefs: ["E-C1"]
            )
        ]

        XCTAssertNil(coordinator.ingest(speaker: .user, text: "I will check it.", isFinal: true, baseline: baseline, clientFacts: facts))
        XCTAssertNil(coordinator.ingest(speaker: .client, text: "Can you", isFinal: false, baseline: baseline, clientFacts: facts))

        let request = coordinator.ingest(
            speaker: .client,
            text: "Can you add Google login too?",
            isFinal: true,
            baseline: baseline,
            clientFacts: facts
        )

        XCTAssertEqual(request?.clientSaid, "Can you add Google login too?")
        XCTAssertEqual(request?.baselineVersion, 2)
        XCTAssertEqual(request?.confirmedRequirements, ["Email/password login"])
        XCTAssertEqual(request?.clientFacts, ["Launch this week"])
        XCTAssertEqual(request?.recentTurns.map(\.speaker), [.user, .client])
    }

    func testSpokenReplyContractDefaultsToShortA2B1Assistance() {
        let policy = SpokenReplyPolicy()
        XCTAssertEqual(policy.maxSentences, 3)
        XCTAssertEqual(policy.englishLevel, "A2-B1")
        XCTAssertTrue(policy.includeVietnameseHint)
        XCTAssertFalse(policy.allowUnverifiedCommitments)
    }
}
