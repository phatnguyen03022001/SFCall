import Foundation
import CSQLite

public final class SQLiteCaseStore: @unchecked Sendable {
    private var db: OpaquePointer?

    public init(url: URL) throws {
        if sqlite3_open(url.path, &db) != SQLITE_OK {
            let message = db.map { String(cString: sqlite3_errmsg($0)) } ?? "Unable to open SQLite database"
            if let db { sqlite3_close(db) }
            throw CaseStoreError.sqliteFailure(message)
        }
        try execute("PRAGMA foreign_keys = ON;")
        try migrate()
    }

    deinit {
        if let db { sqlite3_close(db) }
    }

    @discardableResult
    public func createClient(
        displayName: String,
        platform: String? = nil,
        platformRef: String? = nil
    ) throws -> ClientRecord {
        let record = ClientRecord(displayName: displayName, platform: platform, platformRef: platformRef)
        try run(
            "INSERT INTO clients(id, display_name, platform, platform_ref) VALUES(?,?,?,?)",
            [.text(record.id.uuidString), .text(displayName), .optionalText(platform), .optionalText(platformRef)]
        )
        return record
    }

    @discardableResult
    public func appendClientFact(
        clientID: UUID,
        kind: ClientFactKind,
        value: String,
        evidenceRefs: [String]
    ) throws -> ClientFactRecord {
        let fact = ClientFactRecord(clientID: clientID, kind: kind, value: value, evidenceRefs: evidenceRefs)
        try run(
            "INSERT INTO client_facts(id, client_id, kind, value, evidence_refs, created_at) VALUES(?,?,?,?,?,?)",
            [.text(fact.id.uuidString), .text(clientID.uuidString), .text(kind.rawValue), .text(value), .text(encodeStrings(evidenceRefs)), .double(fact.createdAt.timeIntervalSince1970)]
        )
        return fact
    }

    public func clientFacts(for clientID: UUID) throws -> [ClientFactRecord] {
        try query(
            "SELECT id, kind, value, evidence_refs, created_at FROM client_facts WHERE client_id = ? ORDER BY created_at, rowid",
            [.text(clientID.uuidString)]
        ) { stmt in
            ClientFactRecord(
                id: UUID(uuidString: text(stmt, 0))!,
                clientID: clientID,
                kind: ClientFactKind(rawValue: text(stmt, 1)) ?? .other,
                value: text(stmt, 2),
                evidenceRefs: decodeStrings(text(stmt, 3)),
                createdAt: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 4))
            )
        }
    }

    @discardableResult
    public func createCase(clientID: UUID, title: String) throws -> CaseRecord {
        let record = CaseRecord(clientID: clientID, title: title)
        try run(
            "INSERT INTO cases(id, client_id, title, baseline_version) VALUES(?,?,?,0)",
            [.text(record.id.uuidString), .text(clientID.uuidString), .text(title)]
        )
        return record
    }

    public func client(forCase caseID: UUID) throws -> ClientRecord {
        let rows: [ClientRecord] = try query(
            "SELECT c.id, c.display_name, c.platform, c.platform_ref FROM clients c JOIN cases k ON k.client_id = c.id WHERE k.id = ?",
            [.text(caseID.uuidString)]
        ) { stmt in
            ClientRecord(
                id: UUID(uuidString: text(stmt, 0))!,
                displayName: text(stmt, 1),
                platform: optionalText(stmt, 2),
                platformRef: optionalText(stmt, 3)
            )
        }
        guard let first = rows.first else { throw CaseStoreError.unknownCase(caseID) }
        return first
    }

    @discardableResult
    public func addRequirement(
        caseID: UUID,
        owner: RequirementOwner,
        text requirementText: String,
        status: RequirementStatus,
        evidenceRefs: [String]
    ) throws -> RequirementRecord {
        let record = RequirementRecord(caseID: caseID, owner: owner, text: requirementText, status: status, evidenceRefs: evidenceRefs)
        try transaction {
            try run(
                "INSERT INTO requirements(id, case_id, owner, text, status, evidence_refs) VALUES(?,?,?,?,?,?)",
                [.text(record.id.uuidString), .text(caseID.uuidString), .text(owner.rawValue), .text(requirementText), .text(status.rawValue), .text(encodeStrings(evidenceRefs))]
            )
            try appendEvent(caseID: caseID, kind: .requirementAdded, detail: record.id.uuidString)
            if status == .confirmed {
                try bumpBaseline(caseID: caseID, detail: record.id.uuidString)
            }
        }
        return record
    }

    public func confirmRequirement(_ requirementID: UUID, caseID: UUID, evidenceRefs: [String]) throws {
        let rows: [RequirementRecord] = try query(
            "SELECT owner, text, status, evidence_refs FROM requirements WHERE id = ? AND case_id = ?",
            [.text(requirementID.uuidString), .text(caseID.uuidString)]
        ) { stmt in
            RequirementRecord(
                id: requirementID,
                caseID: caseID,
                owner: RequirementOwner(rawValue: text(stmt, 0))!,
                text: text(stmt, 1),
                status: RequirementStatus(rawValue: text(stmt, 2))!,
                evidenceRefs: decodeStrings(text(stmt, 3))
            )
        }
        guard let current = rows.first else { throw CaseStoreError.unknownRequirement(requirementID) }
        guard current.status != .confirmed else { return }
        let merged = current.evidenceRefs + evidenceRefs.filter { !current.evidenceRefs.contains($0) }
        try transaction {
            try run(
                "UPDATE requirements SET status = ?, evidence_refs = ? WHERE id = ?",
                [.text(RequirementStatus.confirmed.rawValue), .text(encodeStrings(merged)), .text(requirementID.uuidString)]
            )
            try appendEvent(caseID: caseID, kind: .requirementConfirmed, detail: requirementID.uuidString)
            try bumpBaseline(caseID: caseID, detail: requirementID.uuidString)
        }
    }

    public func baseline(for caseID: UUID) throws -> CaseBaseline {
        let versions: [Int] = try query(
            "SELECT baseline_version FROM cases WHERE id = ?",
            [.text(caseID.uuidString)]
        ) { Int(sqlite3_column_int($0, 0)) }
        guard let version = versions.first else { throw CaseStoreError.unknownCase(caseID) }
        let records: [RequirementRecord] = try query(
            "SELECT id, owner, text, status, evidence_refs FROM requirements WHERE case_id = ? AND status = ? ORDER BY rowid",
            [.text(caseID.uuidString), .text(RequirementStatus.confirmed.rawValue)]
        ) { stmt in
            RequirementRecord(
                id: UUID(uuidString: text(stmt, 0))!,
                caseID: caseID,
                owner: RequirementOwner(rawValue: text(stmt, 1))!,
                text: text(stmt, 2),
                status: RequirementStatus(rawValue: text(stmt, 3))!,
                evidenceRefs: decodeStrings(text(stmt, 4))
            )
        }
        return CaseBaseline(version: version, requirements: records)
    }

    public func appendEvidence(_ record: EvidenceRecord) throws {
        do {
            try run(
                "INSERT INTO evidence(id, case_id, kind, source_ref, content, observed_at) VALUES(?,?,?,?,?,?)",
                [.text(record.id), .text(record.caseID.uuidString), .text(record.kind.rawValue), .text(record.sourceRef), .text(record.content), .double(record.observedAt.timeIntervalSince1970)]
            )
        } catch CaseStoreError.sqliteFailure(let message) where message.contains("UNIQUE constraint failed: evidence.id") {
            throw CaseStoreError.duplicateEvidence(record.id)
        }
    }

    public func evidence(for caseID: UUID) throws -> [EvidenceRecord] {
        try query(
            "SELECT id, kind, source_ref, content, observed_at FROM evidence WHERE case_id = ? ORDER BY observed_at, rowid",
            [.text(caseID.uuidString)]
        ) { stmt in
            EvidenceRecord(
                id: text(stmt, 0),
                caseID: caseID,
                kind: EvidenceKind(rawValue: text(stmt, 1)) ?? .other,
                sourceRef: text(stmt, 2),
                content: text(stmt, 3),
                observedAt: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 4))
            )
        }
    }

    @discardableResult
    public func startCallSession(
        caseID: UUID,
        retention: CallRetentionPolicy = CallRetentionPolicy()
    ) throws -> CallSessionRecord {
        _ = try baseline(for: caseID)
        let session = CallSessionRecord(caseID: caseID, retention: retention)
        try run(
            "INSERT INTO call_sessions(id, case_id, started_at, audio_retention, transcript_retention, persist_structured_memory) VALUES(?,?,?,?,?,?)",
            [
                .text(session.id.uuidString),
                .text(caseID.uuidString),
                .double(session.startedAt.timeIntervalSince1970),
                .text(retention.audio.rawValue),
                .text(retention.transcript.rawValue),
                .int(retention.persistStructuredMemory ? 1 : 0)
            ]
        )
        return session
    }

    public func appendTranscriptTurn(
        sessionID: UUID,
        speaker: TranscriptSpeaker,
        text: String,
        isFinal: Bool
    ) throws {
        let sessions = try sessionRows(sessionID: sessionID)
        guard let session = sessions.first else { throw CaseStoreError.unknownSession(sessionID) }
        guard session.retention.transcript == .persist else { return }
        let turn = TranscriptTurnRecord(sessionID: sessionID, speaker: speaker, text: text, isFinal: isFinal)
        try run(
            "INSERT INTO transcript_turns(id, session_id, speaker, text, is_final, created_at) VALUES(?,?,?,?,?,?)",
            [
                .text(turn.id.uuidString),
                .text(sessionID.uuidString),
                .text(speaker.rawValue),
                .text(text),
                .int(isFinal ? 1 : 0),
                .double(turn.createdAt.timeIntervalSince1970)
            ]
        )
    }

    public func callSessions(for caseID: UUID) throws -> [CallSessionRecord] {
        try query(
            "SELECT id, started_at, audio_retention, transcript_retention, persist_structured_memory FROM call_sessions WHERE case_id = ? ORDER BY started_at, rowid",
            [.text(caseID.uuidString)]
        ) { stmt in
            CallSessionRecord(
                id: UUID(uuidString: text(stmt, 0))!,
                caseID: caseID,
                startedAt: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 1)),
                retention: CallRetentionPolicy(
                    audio: AudioRetention(rawValue: text(stmt, 2)) ?? .never,
                    transcript: TranscriptRetention(rawValue: text(stmt, 3)) ?? .ephemeral,
                    persistStructuredMemory: sqlite3_column_int(stmt, 4) != 0
                )
            )
        }
    }

    public func transcriptTurns(for sessionID: UUID) throws -> [TranscriptTurnRecord] {
        _ = try requireSession(sessionID)
        return try query(
            "SELECT id, speaker, text, is_final, created_at FROM transcript_turns WHERE session_id = ? ORDER BY created_at, rowid",
            [.text(sessionID.uuidString)]
        ) { stmt in
            TranscriptTurnRecord(
                id: UUID(uuidString: text(stmt, 0))!,
                sessionID: sessionID,
                speaker: TranscriptSpeaker(rawValue: text(stmt, 1))!,
                text: text(stmt, 2),
                isFinal: sqlite3_column_int(stmt, 3) != 0,
                createdAt: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 4))
            )
        }
    }

    private func sessionRows(sessionID: UUID) throws -> [CallSessionRecord] {
        try query(
            "SELECT case_id, started_at, audio_retention, transcript_retention, persist_structured_memory FROM call_sessions WHERE id = ?",
            [.text(sessionID.uuidString)]
        ) { stmt in
            CallSessionRecord(
                id: sessionID,
                caseID: UUID(uuidString: text(stmt, 0))!,
                startedAt: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 1)),
                retention: CallRetentionPolicy(
                    audio: AudioRetention(rawValue: text(stmt, 2)) ?? .never,
                    transcript: TranscriptRetention(rawValue: text(stmt, 3)) ?? .ephemeral,
                    persistStructuredMemory: sqlite3_column_int(stmt, 4) != 0
                )
            )
        }
    }

    private func requireSession(_ sessionID: UUID) throws -> CallSessionRecord {
        guard let session = try sessionRows(sessionID: sessionID).first else {
            throw CaseStoreError.unknownSession(sessionID)
        }
        return session
    }

    public func events(for caseID: UUID) throws -> [CaseEvent] {
        try query(
            "SELECT id, kind, created_at, detail FROM case_events WHERE case_id = ? ORDER BY created_at, rowid",
            [.text(caseID.uuidString)]
        ) { stmt in
            CaseEvent(
                id: UUID(uuidString: text(stmt, 0))!,
                caseID: caseID,
                kind: CaseEventKind(rawValue: text(stmt, 1))!,
                createdAt: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 2)),
                detail: text(stmt, 3)
            )
        }
    }

    private func migrate() throws {
        try execute("""
        CREATE TABLE IF NOT EXISTS clients(
          id TEXT PRIMARY KEY,
          display_name TEXT NOT NULL,
          platform TEXT,
          platform_ref TEXT
        );
        CREATE TABLE IF NOT EXISTS client_facts(
          id TEXT PRIMARY KEY,
          client_id TEXT NOT NULL REFERENCES clients(id),
          kind TEXT NOT NULL,
          value TEXT NOT NULL,
          evidence_refs TEXT NOT NULL,
          created_at REAL NOT NULL
        );
        CREATE TABLE IF NOT EXISTS cases(
          id TEXT PRIMARY KEY,
          client_id TEXT NOT NULL REFERENCES clients(id),
          title TEXT NOT NULL,
          baseline_version INTEGER NOT NULL DEFAULT 0
        );
        CREATE TABLE IF NOT EXISTS requirements(
          id TEXT PRIMARY KEY,
          case_id TEXT NOT NULL REFERENCES cases(id),
          owner TEXT NOT NULL,
          text TEXT NOT NULL,
          status TEXT NOT NULL,
          evidence_refs TEXT NOT NULL
        );
        CREATE TABLE IF NOT EXISTS evidence(
          id TEXT PRIMARY KEY,
          case_id TEXT NOT NULL REFERENCES cases(id),
          kind TEXT NOT NULL,
          source_ref TEXT NOT NULL,
          content TEXT NOT NULL,
          observed_at REAL NOT NULL
        );
        CREATE TABLE IF NOT EXISTS case_events(
          id TEXT PRIMARY KEY,
          case_id TEXT NOT NULL REFERENCES cases(id),
          kind TEXT NOT NULL,
          created_at REAL NOT NULL,
          detail TEXT NOT NULL
        );
        CREATE TABLE IF NOT EXISTS call_sessions(
          id TEXT PRIMARY KEY,
          case_id TEXT NOT NULL REFERENCES cases(id),
          started_at REAL NOT NULL,
          audio_retention TEXT NOT NULL,
          transcript_retention TEXT NOT NULL,
          persist_structured_memory INTEGER NOT NULL
        );
        CREATE TABLE IF NOT EXISTS transcript_turns(
          id TEXT PRIMARY KEY,
          session_id TEXT NOT NULL REFERENCES call_sessions(id),
          speaker TEXT NOT NULL,
          text TEXT NOT NULL,
          is_final INTEGER NOT NULL,
          created_at REAL NOT NULL
        );
        """)
    }

    private func appendEvent(caseID: UUID, kind: CaseEventKind, detail: String) throws {
        let event = CaseEvent(caseID: caseID, kind: kind, detail: detail)
        try run(
            "INSERT INTO case_events(id, case_id, kind, created_at, detail) VALUES(?,?,?,?,?)",
            [.text(event.id.uuidString), .text(caseID.uuidString), .text(kind.rawValue), .double(event.createdAt.timeIntervalSince1970), .text(detail)]
        )
    }

    private func bumpBaseline(caseID: UUID, detail: String) throws {
        try run("UPDATE cases SET baseline_version = baseline_version + 1 WHERE id = ?", [.text(caseID.uuidString)])
        try appendEvent(caseID: caseID, kind: .baselineChanged, detail: detail)
    }

    private func transaction(_ body: () throws -> Void) throws {
        try execute("BEGIN IMMEDIATE;")
        do {
            try body()
            try execute("COMMIT;")
        } catch {
            try? execute("ROLLBACK;")
            throw error
        }
    }

    private func execute(_ sql: String) throws {
        guard let db else { throw CaseStoreError.sqliteFailure("Database closed") }
        var errorMessage: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, sql, nil, nil, &errorMessage) != SQLITE_OK {
            let message = errorMessage.map { String(cString: $0) } ?? String(cString: sqlite3_errmsg(db))
            sqlite3_free(errorMessage)
            throw CaseStoreError.sqliteFailure(message)
        }
    }

    private enum Binding {
        case text(String)
        case optionalText(String?)
        case double(Double)
        case int(Int32)
    }

    private func run(_ sql: String, _ bindings: [Binding]) throws {
        guard let db else { throw CaseStoreError.sqliteFailure("Database closed") }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            throw CaseStoreError.sqliteFailure(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }
        try bind(bindings, to: stmt)
        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw CaseStoreError.sqliteFailure(String(cString: sqlite3_errmsg(db)))
        }
    }

    private func query<T>(_ sql: String, _ bindings: [Binding], map: (OpaquePointer) -> T) throws -> [T] {
        guard let db else { throw CaseStoreError.sqliteFailure("Database closed") }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            throw CaseStoreError.sqliteFailure(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }
        try bind(bindings, to: stmt)
        var result: [T] = []
        while true {
            switch sqlite3_step(stmt) {
            case SQLITE_ROW: result.append(map(stmt))
            case SQLITE_DONE: return result
            default: throw CaseStoreError.sqliteFailure(String(cString: sqlite3_errmsg(db)))
            }
        }
    }

    private func bind(_ bindings: [Binding], to stmt: OpaquePointer) throws {
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        for (offset, binding) in bindings.enumerated() {
            let index = Int32(offset + 1)
            let rc: Int32
            switch binding {
            case .text(let value):
                rc = sqlite3_bind_text(stmt, index, value, -1, transient)
            case .optionalText(let value):
                if let value { rc = sqlite3_bind_text(stmt, index, value, -1, transient) }
                else { rc = sqlite3_bind_null(stmt, index) }
            case .double(let value):
                rc = sqlite3_bind_double(stmt, index, value)
            case .int(let value):
                rc = sqlite3_bind_int(stmt, index, value)
            }
            if rc != SQLITE_OK { throw CaseStoreError.sqliteFailure("SQLite bind failed: \(rc)") }
        }
    }
}

private func text(_ stmt: OpaquePointer, _ index: Int32) -> String {
    guard let pointer = sqlite3_column_text(stmt, index) else { return "" }
    return String(cString: pointer)
}

private func optionalText(_ stmt: OpaquePointer, _ index: Int32) -> String? {
    sqlite3_column_type(stmt, index) == SQLITE_NULL ? nil : text(stmt, index)
}

private func encodeStrings(_ values: [String]) -> String {
    let data = (try? JSONEncoder().encode(values)) ?? Data("[]".utf8)
    return String(data: data, encoding: .utf8) ?? "[]"
}

private func decodeStrings(_ value: String) -> [String] {
    guard let data = value.data(using: .utf8) else { return [] }
    return (try? JSONDecoder().decode([String].self, from: data)) ?? []
}
