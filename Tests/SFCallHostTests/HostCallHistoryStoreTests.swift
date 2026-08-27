#if os(macOS)
import Foundation
import XCTest
import SFCallCore
@testable import SFCallHostSupport

final class HostCallHistoryStoreTests: XCTestCase {
    @MainActor
    func testPrepareReusesCaseAndPersistsOnlyFinalTurns() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("SFCallHistoryTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let databaseURL = root.appendingPathComponent("history.sqlite3")
        let suiteName = "SFCallHistoryTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let firstStore = try HostCallHistoryStore(databaseURL: databaseURL, defaults: defaults)
        let first = try firstStore.prepareSession()

        XCTAssertEqual(first.session.retention.audio, .never)
        XCTAssertEqual(first.session.retention.transcript, .persist)
        XCTAssertTrue(first.session.retention.persistStructuredMemory)

        try firstStore.appendTranscriptTurn(
            sessionID: first.session.id,
            speaker: .client,
            text: "partial",
            isFinal: false
        )
        try firstStore.appendTranscriptTurn(
            sessionID: first.session.id,
            speaker: .client,
            text: "Final client turn",
            isFinal: true
        )
        try firstStore.appendTranscriptTurn(
            sessionID: first.session.id,
            speaker: .user,
            text: "Final user turn",
            isFinal: true
        )

        let turns = try firstStore.transcriptTurns(for: first.session.id)
        XCTAssertEqual(turns.map(\.text), ["Final client turn", "Final user turn"])
        XCTAssertEqual(turns.map(\.speaker), [.client, .user])

        let secondStore = try HostCallHistoryStore(databaseURL: databaseURL, defaults: defaults)
        let second = try secondStore.prepareSession()

        XCTAssertEqual(second.caseID, first.caseID)
        XCTAssertNotEqual(second.session.id, first.session.id)
    }
}
#endif
