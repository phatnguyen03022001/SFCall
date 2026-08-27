import XCTest
@testable import SFCallCore

final class CaseMemoryTests: XCTestCase {
    func testOnlyConfirmedRequirementsEnterBaselineAndOwnerIsPreserved() throws {
        let store = InMemoryCaseStore()
        let client = try store.createClient(displayName: "Acme")
        let caseRecord = try store.createCase(clientID: client.id, title: "Checkout")

        _ = try store.addRequirement(
            caseID: caseRecord.id,
            owner: .client,
            text: "Support card payments",
            status: .confirmed,
            evidenceRefs: ["E-001"]
        )
        _ = try store.addRequirement(
            caseID: caseRecord.id,
            owner: .user,
            text: "Use Stripe unless client objects",
            status: .proposed,
            evidenceRefs: ["E-002"]
        )

        let baseline = try store.baseline(for: caseRecord.id)
        XCTAssertEqual(baseline.version, 1)
        XCTAssertEqual(baseline.requirements.count, 1)
        XCTAssertEqual(baseline.requirements.first?.owner, .client)
        XCTAssertEqual(baseline.requirements.first?.text, "Support card payments")
    }

    func testEvidenceIsAppendOnly() throws {
        let store = InMemoryCaseStore()
        let client = try store.createClient(displayName: "Acme")
        let caseRecord = try store.createCase(clientID: client.id, title: "Checkout")
        let evidence = EvidenceRecord(
            id: "E-001",
            caseID: caseRecord.id,
            kind: .clientMessage,
            sourceRef: "call:1:turn:4",
            content: "Client asked for Google login."
        )

        try store.appendEvidence(evidence)
        XCTAssertThrowsError(try store.appendEvidence(evidence)) { error in
            XCTAssertEqual(error as? CaseStoreError, .duplicateEvidence("E-001"))
        }
    }

    func testConfirmingMaterialRequirementBumpsBaselineAndPreservesHistory() throws {
        let store = InMemoryCaseStore()
        let client = try store.createClient(displayName: "Acme")
        let caseRecord = try store.createCase(clientID: client.id, title: "Auth")
        let requirement = try store.addRequirement(
            caseID: caseRecord.id,
            owner: .client,
            text: "Google login",
            status: .needsConfirmation,
            evidenceRefs: ["E-010"]
        )

        XCTAssertEqual(try store.baseline(for: caseRecord.id).version, 0)
        try store.confirmRequirement(requirement.id, caseID: caseRecord.id, evidenceRefs: ["E-011"])

        let baseline = try store.baseline(for: caseRecord.id)
        XCTAssertEqual(baseline.version, 1)
        XCTAssertEqual(baseline.requirements.map(\.text), ["Google login"])

        let events = try store.events(for: caseRecord.id)
        XCTAssertTrue(events.contains { $0.kind == .requirementAdded })
        XCTAssertTrue(events.contains { $0.kind == .requirementConfirmed })
        XCTAssertTrue(events.contains { $0.kind == .baselineChanged })
    }

    func testCallRetentionDefaultsProtectRawData() {
        let policy = CallRetentionPolicy()
        XCTAssertEqual(policy.audio, .never)
        XCTAssertEqual(policy.transcript, .ephemeral)
        XCTAssertTrue(policy.persistStructuredMemory)
    }
}
