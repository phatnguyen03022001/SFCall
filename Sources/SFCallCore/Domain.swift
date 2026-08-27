import Foundation

public enum RequirementOwner: String, Codable, Sendable {
    case client
    case user
    case mutual
}

public enum RequirementStatus: String, Codable, Sendable {
    case confirmed
    case proposed
    case needsConfirmation
}

public enum EvidenceKind: String, Codable, Sendable {
    case jobPost
    case clientMessage
    case contract
    case offer
    case file
    case screenshot
    case platformState
    case test
    case log
    case userStatement
    case other
}

public enum CaseEventKind: String, Codable, Sendable {
    case requirementAdded
    case requirementConfirmed
    case baselineChanged
}

public enum AudioRetention: String, Codable, Sendable {
    case never
    case persist
}

public enum TranscriptRetention: String, Codable, Sendable {
    case ephemeral
    case persist
}

public struct CallRetentionPolicy: Equatable, Codable, Sendable {
    public var audio: AudioRetention
    public var transcript: TranscriptRetention
    public var persistStructuredMemory: Bool

    public init(
        audio: AudioRetention = .never,
        transcript: TranscriptRetention = .ephemeral,
        persistStructuredMemory: Bool = true
    ) {
        self.audio = audio
        self.transcript = transcript
        self.persistStructuredMemory = persistStructuredMemory
    }
}


public enum TranscriptSpeaker: String, Codable, Sendable {
    case client
    case user
}

public struct CallSessionRecord: Equatable, Codable, Sendable {
    public let id: UUID
    public let caseID: UUID
    public let startedAt: Date
    public let retention: CallRetentionPolicy

    public init(
        id: UUID = UUID(),
        caseID: UUID,
        startedAt: Date = Date(),
        retention: CallRetentionPolicy = CallRetentionPolicy()
    ) {
        self.id = id
        self.caseID = caseID
        self.startedAt = startedAt
        self.retention = retention
    }
}

public struct TranscriptTurnRecord: Equatable, Codable, Sendable {
    public let id: UUID
    public let sessionID: UUID
    public let speaker: TranscriptSpeaker
    public let text: String
    public let isFinal: Bool
    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        sessionID: UUID,
        speaker: TranscriptSpeaker,
        text: String,
        isFinal: Bool,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.sessionID = sessionID
        self.speaker = speaker
        self.text = text
        self.isFinal = isFinal
        self.createdAt = createdAt
    }
}

public struct ClientRecord: Equatable, Codable, Sendable {
    public let id: UUID
    public var displayName: String
    public var platform: String?
    public var platformRef: String?

    public init(
        id: UUID = UUID(),
        displayName: String,
        platform: String? = nil,
        platformRef: String? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.platform = platform
        self.platformRef = platformRef
    }
}

public enum ClientFactKind: String, Codable, Sendable {
    case company
    case role
    case timezone
    case preference
    case priority
    case constraint
    case promise
    case observedSignal
    case other
}

public struct ClientFactRecord: Equatable, Codable, Sendable {
    public let id: UUID
    public let clientID: UUID
    public let kind: ClientFactKind
    public let value: String
    public let evidenceRefs: [String]
    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        clientID: UUID,
        kind: ClientFactKind,
        value: String,
        evidenceRefs: [String],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.clientID = clientID
        self.kind = kind
        self.value = value
        self.evidenceRefs = evidenceRefs
        self.createdAt = createdAt
    }
}

public struct CaseRecord: Equatable, Codable, Sendable {
    public let id: UUID
    public let clientID: UUID
    public var title: String

    public init(id: UUID = UUID(), clientID: UUID, title: String) {
        self.id = id
        self.clientID = clientID
        self.title = title
    }
}

public struct RequirementRecord: Equatable, Codable, Sendable {
    public let id: UUID
    public let caseID: UUID
    public let owner: RequirementOwner
    public let text: String
    public var status: RequirementStatus
    public var evidenceRefs: [String]

    public init(
        id: UUID = UUID(),
        caseID: UUID,
        owner: RequirementOwner,
        text: String,
        status: RequirementStatus,
        evidenceRefs: [String]
    ) {
        self.id = id
        self.caseID = caseID
        self.owner = owner
        self.text = text
        self.status = status
        self.evidenceRefs = evidenceRefs
    }
}

public struct EvidenceRecord: Equatable, Codable, Sendable {
    public let id: String
    public let caseID: UUID
    public let kind: EvidenceKind
    public let sourceRef: String
    public let content: String
    public let observedAt: Date

    public init(
        id: String,
        caseID: UUID,
        kind: EvidenceKind,
        sourceRef: String,
        content: String,
        observedAt: Date = Date()
    ) {
        self.id = id
        self.caseID = caseID
        self.kind = kind
        self.sourceRef = sourceRef
        self.content = content
        self.observedAt = observedAt
    }
}

public struct CaseEvent: Equatable, Codable, Sendable {
    public let id: UUID
    public let caseID: UUID
    public let kind: CaseEventKind
    public let createdAt: Date
    public let detail: String

    public init(
        id: UUID = UUID(),
        caseID: UUID,
        kind: CaseEventKind,
        createdAt: Date = Date(),
        detail: String
    ) {
        self.id = id
        self.caseID = caseID
        self.kind = kind
        self.createdAt = createdAt
        self.detail = detail
    }
}

public struct CaseBaseline: Equatable, Codable, Sendable {
    public let version: Int
    public let requirements: [RequirementRecord]

    public init(version: Int, requirements: [RequirementRecord]) {
        self.version = version
        self.requirements = requirements
    }
}

public enum CaseStoreError: Error, Equatable, Sendable {
    case unknownClient(UUID)
    case unknownCase(UUID)
    case unknownRequirement(UUID)
    case duplicateEvidence(String)
    case unknownSession(UUID)
    case sqliteFailure(String)
}
