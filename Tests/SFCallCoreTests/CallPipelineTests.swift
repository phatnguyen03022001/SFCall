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

    func testEightConsecutiveUserFinalsRemainOneContextTurnForNextClientRequest() {
        let coordinator = CallTurnCoordinator()
        let baseline = CaseBaseline(version: 0, requirements: [])
        let userFragments = [
            "I can deliver",
            "the first milestone",
            "next Friday",
            "but I cannot",
            "commit to",
            "the full scope",
            "at this",
            "price",
        ]

        for fragment in userFragments {
            XCTAssertNil(
                coordinator.ingest(
                    speaker: .user,
                    text: fragment,
                    isFinal: true,
                    baseline: baseline,
                    clientFacts: []
                )
            )
        }

        let request = coordinator.ingest(
            speaker: .client,
            text: "Can you reduce the price?",
            isFinal: true,
            baseline: baseline,
            clientFacts: []
        )

        XCTAssertEqual(
            request?.recentTurns,
            [
                ConversationTurn(
                    speaker: .user,
                    text: "I can deliver the first milestone next Friday but I cannot commit to the full scope at this price"
                ),
                ConversationTurn(speaker: .client, text: "Can you reduce the price?"),
            ]
        )
    }

    func testConsecutiveClientFinalsCoalesceContextWhileEachStillCreatesRequest() {
        let router = LiveCallRouter()
        let baseline = CaseBaseline(version: 0, requirements: [])

        let firstRequest = router.ingestRemote(
            text: "We need",
            isFinal: true,
            baseline: baseline,
            clientFacts: []
        )
        let secondRequest = router.ingestRemote(
            text: "delivery Friday",
            isFinal: true,
            baseline: baseline,
            clientFacts: []
        )

        XCTAssertEqual(firstRequest?.clientSaid, "We need")
        XCTAssertEqual(secondRequest?.clientSaid, "delivery Friday")
        XCTAssertEqual(
            secondRequest?.recentTurns,
            [ConversationTurn(speaker: .client, text: "We need delivery Friday")]
        )
        XCTAssertEqual(
            router.recentTurns,
            [ConversationTurn(speaker: .client, text: "We need delivery Friday")]
        )
    }

    func testSpokenReplyContractDefaultsToShortA2B1Assistance() {
        let policy = SpokenReplyPolicy()
        XCTAssertEqual(policy.maxSentences, 3)
        XCTAssertEqual(policy.englishLevel, "A2-B1")
        XCTAssertTrue(policy.includeVietnameseHint)
        XCTAssertFalse(policy.allowUnverifiedCommitments)
    }
}
