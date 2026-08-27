import XCTest
@testable import SFCallCore

final class CallSessionTests: XCTestCase {
    func testEphemeralTranscriptIsNotPersistedButSessionMetadataIs() throws {
        let url = temporaryDatabaseURL()
        defer { try? FileManager.default.removeItem(at: url) }
        var caseID: UUID!
        var sessionID: UUID!

        do {
            let store = try SQLiteCaseStore(url: url)
            let client = try store.createClient(displayName: "Acme")
            let caseRecord = try store.createCase(clientID: client.id, title: "Discovery")
            caseID = caseRecord.id
            let session = try store.startCallSession(caseID: caseRecord.id)
            sessionID = session.id
            try store.appendTranscriptTurn(
                sessionID: session.id,
                speaker: .client,
                text: "Can you add Google login?",
                isFinal: true
            )
        }

        do {
            let reopened = try SQLiteCaseStore(url: url)
            XCTAssertEqual(try reopened.callSessions(for: caseID).map(\.id), [sessionID!])
            XCTAssertTrue(try reopened.transcriptTurns(for: sessionID).isEmpty)
        }
    }

    func testPersistTranscriptStoresClientAndUserAsSeparateSpeakers() throws {
        let url = temporaryDatabaseURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = try SQLiteCaseStore(url: url)
        let client = try store.createClient(displayName: "Acme")
        let caseRecord = try store.createCase(clientID: client.id, title: "Discovery")
        let session = try store.startCallSession(
            caseID: caseRecord.id,
            retention: CallRetentionPolicy(transcript: .persist)
        )

        try store.appendTranscriptTurn(sessionID: session.id, speaker: .client, text: "What is the timeline?", isFinal: true)
        try store.appendTranscriptTurn(sessionID: session.id, speaker: .user, text: "I will confirm after the call.", isFinal: true)

        let turns = try store.transcriptTurns(for: session.id)
        XCTAssertEqual(turns.map(\.speaker), [.client, .user])
        XCTAssertEqual(turns.map(\.text), ["What is the timeline?", "I will confirm after the call."])
    }

    private func temporaryDatabaseURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("sfcall-session-\(UUID().uuidString).sqlite")
    }
}
