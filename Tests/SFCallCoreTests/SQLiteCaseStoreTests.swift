import XCTest
@testable import SFCallCore

final class SQLiteCaseStoreTests: XCTestCase {
    func testPersistsClientCaseRequirementsEvidenceEventsAndClientFactsAcrossReopen() throws {
        let url = temporaryDatabaseURL()
        defer { try? FileManager.default.removeItem(at: url) }

        var caseID: UUID!
        do {
            let store = try SQLiteCaseStore(url: url)
            let client = try store.createClient(
                displayName: "John",
                platform: "UPWORK",
                platformRef: "upwork:freelancer-client-42"
            )
            _ = try store.appendClientFact(
                clientID: client.id,
                kind: .priority,
                value: "Launch before September",
                evidenceRefs: ["E-CLIENT-1"]
            )
            let caseRecord = try store.createCase(clientID: client.id, title: "Auth")
            caseID = caseRecord.id
            try store.appendEvidence(EvidenceRecord(
                id: "E-001",
                caseID: caseRecord.id,
                kind: .clientMessage,
                sourceRef: "call:1:turn:4",
                content: "We need Google login."
            ))
            _ = try store.addRequirement(
                caseID: caseRecord.id,
                owner: .client,
                text: "Google login",
                status: .confirmed,
                evidenceRefs: ["E-001"]
            )
        }

        do {
            let reopened = try SQLiteCaseStore(url: url)
            let baseline = try reopened.baseline(for: caseID)
            XCTAssertEqual(baseline.version, 1)
            XCTAssertEqual(baseline.requirements.map(\.text), ["Google login"])
            XCTAssertEqual(try reopened.evidence(for: caseID).map(\.id), ["E-001"])
            XCTAssertFalse(try reopened.events(for: caseID).isEmpty)

            let client = try reopened.client(forCase: caseID)
            XCTAssertEqual(client.platform, "UPWORK")
            XCTAssertEqual(try reopened.clientFacts(for: client.id).map(\.value), ["Launch before September"])
        }
    }

    func testSQLiteEvidenceIdentityIsAppendOnly() throws {
        let url = temporaryDatabaseURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = try SQLiteCaseStore(url: url)
        let client = try store.createClient(displayName: "Acme", platform: nil, platformRef: nil)
        let caseRecord = try store.createCase(clientID: client.id, title: "Checkout")
        let evidence = EvidenceRecord(
            id: "E-001",
            caseID: caseRecord.id,
            kind: .clientMessage,
            sourceRef: "call:1",
            content: "Original"
        )

        try store.appendEvidence(evidence)
        XCTAssertThrowsError(try store.appendEvidence(evidence)) { error in
            XCTAssertEqual(error as? CaseStoreError, .duplicateEvidence("E-001"))
        }
    }

    private func temporaryDatabaseURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("sfcall-\(UUID().uuidString).sqlite")
    }
}
