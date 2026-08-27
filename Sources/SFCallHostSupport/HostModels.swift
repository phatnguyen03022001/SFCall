#if os(macOS)
import Foundation
import SFCallCore
import SFCallMac

public struct HostSourceItem: Equatable, Identifiable, Sendable {
    public let id: String
    public let kind: CallCaptureSourceKind
    public let title: String

    public init(id: String, kind: CallCaptureSourceKind, title: String) {
        self.id = id
        self.kind = kind
        self.title = title
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
    public let screenCapture: HostPermissionState
    public let systemAudio: HostPermissionState

    public init(
        microphone: HostPermissionState,
        speech: HostPermissionState,
        screenCapture: HostPermissionState,
        systemAudio: HostPermissionState
    ) {
        self.microphone = microphone
        self.speech = speech
        self.screenCapture = screenCapture
        self.systemAudio = systemAudio
    }

    public static let unknown = HostPermissionSnapshot(
        microphone: .notDetermined,
        speech: .notDetermined,
        screenCapture: .notDetermined,
        systemAudio: .notDetermined
    )
}

@MainActor
public protocol HostRuntimeDriving: AnyObject {
    func refreshSources(
        completion: @escaping @MainActor (Result<[HostSourceItem], Error>) -> Void
    )

    func requestPermissions(
        completion: @escaping @MainActor (HostPermissionSnapshot) -> Void
    )

    func start(
        sourceID: String,
        onResponseRequest: @escaping @MainActor @Sendable (ResponseRequest) -> Void,
        completion: @escaping @MainActor (Result<Void, Error>) -> Void
    )

    func stop()
}
#endif
