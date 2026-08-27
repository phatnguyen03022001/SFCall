import Foundation

public final class InMemoryCaseStore: @unchecked Sendable {
    private var clients: [UUID: ClientRecord] = [:]
    private var cases: [UUID: CaseRecord] = [:]
    private var requirements: [UUID: RequirementRecord] = [:]
    private var evidence: [String: EvidenceRecord] = [:]
    private var eventsByCase: [UUID: [CaseEvent]] = [:]
    private var baselineVersionByCase: [UUID: Int] = [:]

    public init() {}

    @discardableResult
    public func createClient(displayName: String, platform: String? = nil, platformRef: String? = nil) throws -> ClientRecord {
        let client = ClientRecord(displayName: displayName, platform: platform, platformRef: platformRef)
        clients[client.id] = client
        return client
    }

    @discardableResult
    public func createCase(clientID: UUID, title: String) throws -> CaseRecord {
        guard clients[clientID] != nil else { throw CaseStoreError.unknownClient(clientID) }
        let record = CaseRecord(clientID: clientID, title: title)
        cases[record.id] = record
        baselineVersionByCase[record.id] = 0
        eventsByCase[record.id] = []
        return record
    }

    @discardableResult
    public func addRequirement(
        caseID: UUID,
        owner: RequirementOwner,
        text: String,
        status: RequirementStatus,
        evidenceRefs: [String]
    ) throws -> RequirementRecord {
        try requireCase(caseID)
        let record = RequirementRecord(
            caseID: caseID,
            owner: owner,
            text: text,
            status: status,
            evidenceRefs: evidenceRefs
        )
        requirements[record.id] = record
        appendEvent(caseID: caseID, kind: .requirementAdded, detail: record.id.uuidString)
        if status == .confirmed {
            bumpBaseline(caseID: caseID, detail: record.id.uuidString)
        }
        return record
    }

    public func confirmRequirement(
        _ requirementID: UUID,
        caseID: UUID,
        evidenceRefs: [String]
    ) throws {
        try requireCase(caseID)
        guard var record = requirements[requirementID], record.caseID == caseID else {
            throw CaseStoreError.unknownRequirement(requirementID)
        }
        guard record.status != .confirmed else { return }
        record.status = .confirmed
        for ref in evidenceRefs where !record.evidenceRefs.contains(ref) {
            record.evidenceRefs.append(ref)
        }
        requirements[requirementID] = record
        appendEvent(caseID: caseID, kind: .requirementConfirmed, detail: requirementID.uuidString)
        bumpBaseline(caseID: caseID, detail: requirementID.uuidString)
    }

    public func baseline(for caseID: UUID) throws -> CaseBaseline {
        try requireCase(caseID)
        let confirmed = requirements.values
            .filter { $0.caseID == caseID && $0.status == .confirmed }
            .sorted { $0.id.uuidString < $1.id.uuidString }
        return CaseBaseline(
            version: baselineVersionByCase[caseID] ?? 0,
            requirements: confirmed
        )
    }

    public func appendEvidence(_ record: EvidenceRecord) throws {
        try requireCase(record.caseID)
        guard evidence[record.id] == nil else { throw CaseStoreError.duplicateEvidence(record.id) }
        evidence[record.id] = record
    }

    public func events(for caseID: UUID) throws -> [CaseEvent] {
        try requireCase(caseID)
        return eventsByCase[caseID] ?? []
    }

    private func requireCase(_ caseID: UUID) throws {
        guard cases[caseID] != nil else { throw CaseStoreError.unknownCase(caseID) }
    }

    private func appendEvent(caseID: UUID, kind: CaseEventKind, detail: String) {
        eventsByCase[caseID, default: []].append(
            CaseEvent(caseID: caseID, kind: kind, detail: detail)
        )
    }

    private func bumpBaseline(caseID: UUID, detail: String) {
        baselineVersionByCase[caseID, default: 0] += 1
        appendEvent(caseID: caseID, kind: .baselineChanged, detail: detail)
    }
}
