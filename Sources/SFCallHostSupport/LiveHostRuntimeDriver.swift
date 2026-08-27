#if os(macOS)
import AVFoundation
import CoreGraphics
import Foundation
import SFCallCore
import SFCallMac
import Speech

@MainActor
public final class LiveHostRuntimeDriver: HostRuntimeDriving {
    private let catalog: ScreenCaptureSourceCatalog
    private var sourceByID: [String: CallCaptureSource] = [:]
    private var activeSession: LiveCallHUDSession?
    private var activeHUD: PrivateHUDWindowController?
    private var screenCaptureState: HostPermissionState = .notDetermined
    private var systemAudioState: HostPermissionState = .notDetermined

    public init(catalog: ScreenCaptureSourceCatalog = ScreenCaptureSourceCatalog()) {
        self.catalog = catalog
    }

    public func refreshSources(
        completion: @escaping @MainActor (Result<[HostSourceItem], Error>) -> Void
    ) {
        let transfer = SourceCatalogTransfer { [weak self] result in
            guard let self else { return }

            switch result {
            case .success(let sources):
                var byID: [String: CallCaptureSource] = [:]
                for source in sources {
                    byID[source.id] = source
                }
                self.sourceByID = byID
                self.screenCaptureState = .authorized
                completion(
                    .success(
                        sources.map {
                            HostSourceItem(id: $0.id, kind: $0.kind, title: $0.title)
                        }
                    )
                )

            case .failure(let error):
                self.sourceByID = [:]
                completion(.failure(error))
            }
        }

        catalog.load { result in
            transfer.submit(result)
        }
    }

    public func requestPermissions(
        completion: @escaping @MainActor (HostPermissionSnapshot) -> Void
    ) {
        requestScreenCaptureIfNeeded { [weak self] in
            guard let self else { return }
            self.requestMicrophoneIfNeeded { [weak self] in
                guard let self else { return }
                self.requestSpeechIfNeeded { [weak self] in
                    guard let self else { return }
                    completion(self.currentPermissionSnapshot())
                }
            }
        }
    }

    public func start(
        sourceID: String,
        onResponseRequest: @escaping @MainActor @Sendable (ResponseRequest) -> Void,
        completion: @escaping @MainActor (Result<Void, Error>) -> Void
    ) {
        guard activeSession == nil else {
            completion(.failure(HostRuntimeDriverError.runtimeAlreadyActive))
            return
        }
        guard let source = sourceByID[sourceID] else {
            completion(.failure(HostRuntimeDriverError.sourceUnavailable))
            return
        }

        let hud = PrivateHUDWindowController()
        let session = LiveCallHUDSession(
            baseline: CaseBaseline(version: 0, requirements: []),
            clientFacts: [],
            hud: hud,
            onResponseRequest: onResponseRequest
        )

        session.start(source: source, localeIdentifier: "en-US") { [weak self] result in
            guard let self else { return }

            switch result {
            case .success:
                self.activeHUD = hud
                self.activeSession = session
                self.screenCaptureState = .authorized
                self.systemAudioState = .authorized
                completion(.success(()))

            case .failure(let error):
                self.activeHUD = nil
                self.activeSession = nil
                completion(.failure(error))
            }
        }
    }

    public func stop() {
        guard let activeSession else { return }
        activeSession.stop()
        self.activeSession = nil
        activeHUD = nil
    }

    private func requestScreenCaptureIfNeeded(
        completion: @escaping @MainActor () -> Void
    ) {
        if CGPreflightScreenCaptureAccess() {
            screenCaptureState = .authorized
            completion()
            return
        }

        screenCaptureState = CGRequestScreenCaptureAccess() ? .authorized : .denied
        completion()
    }

    private func requestMicrophoneIfNeeded(
        completion: @escaping @MainActor () -> Void
    ) {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { _ in
                Task { @MainActor in
                    completion()
                }
            }
        case .authorized, .denied, .restricted:
            completion()
        @unknown default:
            completion()
        }
    }

    private func requestSpeechIfNeeded(
        completion: @escaping @MainActor () -> Void
    ) {
        guard SFSpeechRecognizer.authorizationStatus() == .notDetermined else {
            completion()
            return
        }

        AppleSpeechTranscriber.requestAuthorization { _ in
            Task { @MainActor in
                completion()
            }
        }
    }

    private func currentPermissionSnapshot() -> HostPermissionSnapshot {
        HostPermissionSnapshot(
            microphone: Self.mapMicrophoneStatus(
                AVCaptureDevice.authorizationStatus(for: .audio)
            ),
            speech: Self.mapSpeechStatus(
                SFSpeechRecognizer.authorizationStatus()
            ),
            screenCapture: screenCaptureState,
            systemAudio: systemAudioState
        )
    }

    private static func mapMicrophoneStatus(
        _ status: AVAuthorizationStatus
    ) -> HostPermissionState {
        switch status {
        case .notDetermined:
            .notDetermined
        case .authorized:
            .authorized
        case .denied:
            .denied
        case .restricted:
            .restricted
        @unknown default:
            .unavailable
        }
    }

    private static func mapSpeechStatus(
        _ status: SFSpeechRecognizerAuthorizationStatus
    ) -> HostPermissionState {
        switch status {
        case .notDetermined:
            .notDetermined
        case .authorized:
            .authorized
        case .denied:
            .denied
        case .restricted:
            .restricted
        @unknown default:
            .unavailable
        }
    }
}

private enum HostRuntimeDriverError: LocalizedError, Sendable {
    case sourceUnavailable
    case runtimeAlreadyActive

    var errorDescription: String? {
        switch self {
        case .sourceUnavailable:
            "The selected capture source is no longer available. Refresh sources and try again."
        case .runtimeAlreadyActive:
            "A live SFCall runtime is already active."
        }
    }
}

private final class SourceCatalogTransfer: @unchecked Sendable {
    private let lock = NSLock()
    private var pending: Result<[CallCaptureSource], Error>?
    private let handler: @MainActor (Result<[CallCaptureSource], Error>) -> Void

    @MainActor
    init(
        handler: @escaping @MainActor (Result<[CallCaptureSource], Error>) -> Void
    ) {
        self.handler = handler
    }

    func submit(_ result: Result<[CallCaptureSource], Error>) {
        lock.lock()
        pending = result
        lock.unlock()

        DispatchQueue.main.async { [self] in
            MainActor.assumeIsolated {
                drain()
            }
        }
    }

    @MainActor
    private func drain() {
        lock.lock()
        let result = pending
        pending = nil
        lock.unlock()

        if let result {
            handler(result)
        }
    }
}
#endif
