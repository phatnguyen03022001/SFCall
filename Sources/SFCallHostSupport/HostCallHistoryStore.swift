#if os(macOS)
import Foundation
import SFCallCore

public struct HostPreparedCallSession: Sendable {
    public let caseID: UUID
    public let session: CallSessionRecord
    public let baseline: CaseBaseline
    public let clientFacts: [ClientFactRecord]

    public init(
        caseID: UUID,
        session: CallSessionRecord,
        baseline: CaseBaseline,
        clientFacts: [ClientFactRecord]
    ) {
        self.caseID = caseID
        self.session = session
        self.baseline = baseline
        self.clientFacts = clientFacts
    }
}

public enum HostCallHistoryStoreError: LocalizedError, Sendable {
    case applicationSupportUnavailable

    public var errorDescription: String? {
        switch self {
        case .applicationSupportUnavailable:
            "SFCall could not resolve the Application Support directory."
        }
    }
}

@MainActor
public final class HostCallHistoryStore {
    private static let defaultCaseKey = "SFCall.defaultNegotiationCaseID"

    private let store: SQLiteCaseStore
    private let defaults: UserDefaults

    public convenience init() throws {
        let fileManager = FileManager.default
        guard let root = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            throw HostCallHistoryStoreError.applicationSupportUnavailable
        }
        let directory = root.appendingPathComponent("SFCall", isDirectory: true)
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        try self.init(
            databaseURL: directory.appendingPathComponent("sfcall.sqlite3"),
            defaults: .standard
        )
    }

    public init(databaseURL: URL, defaults: UserDefaults) throws {
        self.store = try SQLiteCaseStore(url: databaseURL)
        self.defaults = defaults
    }

    public func prepareSession() throws -> HostPreparedCallSession {
        let caseID = try resolveOrCreateDefaultCase()
        let baseline = try store.baseline(for: caseID)
        let client = try store.client(forCase: caseID)
        let clientFacts = try store.clientFacts(for: client.id)
        let retention = CallRetentionPolicy(
            audio: .never,
            transcript: .persist,
            persistStructuredMemory: true
        )
        let session = try store.startCallSession(caseID: caseID, retention: retention)
        return HostPreparedCallSession(
            caseID: caseID,
            session: session,
            baseline: baseline,
            clientFacts: clientFacts
        )
    }

    public func appendTranscriptTurn(
        sessionID: UUID,
        speaker: TranscriptSpeaker,
        text: String,
        isFinal: Bool
    ) throws {
        guard isFinal else { return }
        try store.appendTranscriptTurn(
            sessionID: sessionID,
            speaker: speaker,
            text: text,
            isFinal: true
        )
    }

    public func transcriptTurns(for sessionID: UUID) throws -> [TranscriptTurnRecord] {
        try store.transcriptTurns(for: sessionID)
    }

    private func resolveOrCreateDefaultCase() throws -> UUID {
        if let raw = defaults.string(forKey: Self.defaultCaseKey),
           let caseID = UUID(uuidString: raw),
           (try? store.baseline(for: caseID)) != nil {
            return caseID
        }

        let client = try store.createClient(
            displayName: "Local Negotiation",
            platform: "SFCall"
        )
        let record = try store.createCase(
            clientID: client.id,
            title: "Negotiation Calls"
        )
        defaults.set(record.id.uuidString, forKey: Self.defaultCaseKey)
        return record.id
    }
}
#endif
