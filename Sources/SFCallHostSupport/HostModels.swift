#if os(macOS)
import Foundation
import SFCallCore

public struct HostAudioSourceItem: Equatable, Identifiable, Sendable {
    public let id: String
    public let title: String
    public let bundleID: String?
    public let isRunningOutput: Bool

    public init(id: String, title: String, bundleID: String?, isRunningOutput: Bool) {
        self.id = id
        self.title = title
        self.bundleID = bundleID
        self.isRunningOutput = isRunningOutput
    }
}

public enum HostRuntimeStatus: Equatable, Sendable {
    case idle
    case refreshingSources
    case ready
    case requestingPermissions
    case starting
    case running
    case failed(String)
}

public enum HostPermissionState: String, Equatable, Sendable {
    case notDetermined
    case authorized
    case denied
    case restricted
    case unavailable
}

public struct HostPermissionSnapshot: Equatable, Sendable {
    public let microphone: HostPermissionState
    public let speech: HostPermissionState
    public let systemAudio: HostPermissionState

    public init(
        microphone: HostPermissionState,
        speech: HostPermissionState,
        systemAudio: HostPermissionState
    ) {
        self.microphone = microphone
        self.speech = speech
        self.systemAudio = systemAudio
    }

    public static let unknown = HostPermissionSnapshot(
        microphone: .notDetermined,
        speech: .notDetermined,
        systemAudio: .notDetermined
    )
}

public enum HostIntelligenceState: String, Equatable, Sendable {
    case available
    case appleIntelligenceDisabled
    case modelNotReady
    case deviceNotEligible
    case unavailable
}

@MainActor
public protocol HostRuntimeDriving: AnyObject {
    func refreshAudioSources(
        completion: @escaping @MainActor (Result<[HostAudioSourceItem], Error>) -> Void
    )

    func requestPermissions(
        completion: @escaping @MainActor (HostPermissionSnapshot) -> Void
    )

    func intelligenceState() -> HostIntelligenceState

    func start(
        sourceID: String,
        onResponseRequest: @escaping @MainActor @Sendable (ResponseRequest) -> Void,
        completion: @escaping @MainActor (Result<Void, Error>) -> Void
    )

    func stop()
}
#endif
