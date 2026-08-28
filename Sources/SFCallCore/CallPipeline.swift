import Foundation

public struct ConversationTurn: Equatable, Codable, Sendable {
    public let speaker: TranscriptSpeaker
    public let text: String

    public init(speaker: TranscriptSpeaker, text: String) {
        self.speaker = speaker
        self.text = text
    }
}

public struct ResponseRequest: Equatable, Codable, Sendable {
    public let clientSaid: String
    public let baselineVersion: Int
    public let confirmedRequirements: [String]
    public let clientFacts: [String]
    public let recentTurns: [ConversationTurn]

    public init(
        clientSaid: String,
        baselineVersion: Int,
        confirmedRequirements: [String],
        clientFacts: [String],
        recentTurns: [ConversationTurn]
    ) {
        self.clientSaid = clientSaid
        self.baselineVersion = baselineVersion
        self.confirmedRequirements = confirmedRequirements
        self.clientFacts = clientFacts
        self.recentTurns = recentTurns
    }
}

public struct SpokenReplyPolicy: Equatable, Codable, Sendable {
    public let maxSentences: Int
    public let englishLevel: String
    public let includeVietnameseHint: Bool
    public let allowUnverifiedCommitments: Bool

    public init(
        maxSentences: Int = 3,
        englishLevel: String = "A2-B1",
        includeVietnameseHint: Bool = true,
        allowUnverifiedCommitments: Bool = false
    ) {
        self.maxSentences = maxSentences
        self.englishLevel = englishLevel
        self.includeVietnameseHint = includeVietnameseHint
        self.allowUnverifiedCommitments = allowUnverifiedCommitments
    }
}

public final class CallTurnCoordinator: @unchecked Sendable {
    private let maxRecentTurns: Int
    private var finalizedTurns: [ConversationTurn] = []

    public init(maxRecentTurns: Int = 6) {
        self.maxRecentTurns = max(1, maxRecentTurns)
    }

    public func ingest(
        speaker: TranscriptSpeaker,
        text: String,
        isFinal: Bool,
        baseline: CaseBaseline,
        clientFacts: [ClientFactRecord]
    ) -> ResponseRequest? {
        guard isFinal else { return nil }

        insertFinalizedTurn(
            speaker: speaker,
            text: text,
            into: &finalizedTurns,
            maxRecentTurns: maxRecentTurns
        )

        guard speaker == .client else { return nil }

        return ResponseRequest(
            clientSaid: text,
            baselineVersion: baseline.version,
            confirmedRequirements: baseline.requirements.map(\.text),
            clientFacts: clientFacts.map(\.value),
            recentTurns: finalizedTurns
        )
    }
}

public final class LiveCallRouter: @unchecked Sendable {
    private let coordinator: CallTurnCoordinator
    private(set) public var recentTurns: [ConversationTurn] = []
    private let maxRecentTurns: Int

    public init(maxRecentTurns: Int = 6) {
        self.maxRecentTurns = max(1, maxRecentTurns)
        self.coordinator = CallTurnCoordinator(maxRecentTurns: maxRecentTurns)
    }

    public func ingestRemote(
        text: String,
        isFinal: Bool,
        baseline: CaseBaseline,
        clientFacts: [ClientFactRecord]
    ) -> ResponseRequest? {
        ingest(
            speaker: .client,
            text: text,
            isFinal: isFinal,
            baseline: baseline,
            clientFacts: clientFacts
        )
    }

    public func ingestMicrophone(
        text: String,
        isFinal: Bool,
        baseline: CaseBaseline,
        clientFacts: [ClientFactRecord]
    ) -> ResponseRequest? {
        ingest(
            speaker: .user,
            text: text,
            isFinal: isFinal,
            baseline: baseline,
            clientFacts: clientFacts
        )
    }

    private func ingest(
        speaker: TranscriptSpeaker,
        text: String,
        isFinal: Bool,
        baseline: CaseBaseline,
        clientFacts: [ClientFactRecord]
    ) -> ResponseRequest? {
        if isFinal {
            insertFinalizedTurn(
                speaker: speaker,
                text: text,
                into: &recentTurns,
                maxRecentTurns: maxRecentTurns
            )
        }

        return coordinator.ingest(
            speaker: speaker,
            text: text,
            isFinal: isFinal,
            baseline: baseline,
            clientFacts: clientFacts
        )
    }
}

private func insertFinalizedTurn(
    speaker: TranscriptSpeaker,
    text: String,
    into turns: inout [ConversationTurn],
    maxRecentTurns: Int
) {
    let incomingText = text.trimmingCharacters(in: .whitespacesAndNewlines)
    if let previous = turns.last, previous.speaker == speaker, !incomingText.isEmpty {
        let previousText = previous.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let coalescedText = previousText.isEmpty
            ? incomingText
            : previousText + " " + incomingText
        turns[turns.count - 1] = ConversationTurn(speaker: speaker, text: coalescedText)
    } else {
        turns.append(ConversationTurn(speaker: speaker, text: text))
    }

    if turns.count > maxRecentTurns {
        turns.removeFirst(turns.count - maxRecentTurns)
    }
}
