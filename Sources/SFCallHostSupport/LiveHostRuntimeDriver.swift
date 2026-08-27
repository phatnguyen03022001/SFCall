#if os(macOS)
import AVFoundation
import Foundation
import SFCallCore
import SFCallMac
import Speech

@MainActor
public final class LiveHostRuntimeDriver: HostRuntimeDriving {
    private let catalog: AudioProcessSourceCatalog
    private let advisor: any NegotiationAdviceProvider
    private let historyResult: Result<HostCallHistoryStore, Error>

    private var sourceByID: [String: AudioProcessSource] = [:]
    private var activeSession: LiveCallHUDSession?
    private var activeHUD: PrivateHUDWindowController?
    private var systemAudioState: HostPermissionState = .notDetermined
    private var adviceGeneration = 0

    public init(
        catalog: AudioProcessSourceCatalog = AudioProcessSourceCatalog(),
        advisor: any NegotiationAdviceProvider = AppleNegotiationAdvisor(),
        historyStore: HostCallHistoryStore? = nil
    ) {
        self.catalog = catalog
        self.advisor = advisor
        if let historyStore {
            self.historyResult = .success(historyStore)
        } else {
            do {
                self.historyResult = .success(try HostCallHistoryStore())
            } catch {
                self.historyResult = .failure(error)
            }
        }
    }

    public func refreshAudioSources(
        completion: @escaping @MainActor (Result<[HostAudioSourceItem], Error>) -> Void
    ) {
        do {
            let sources = try catalog.load()
            sourceByID = Dictionary(
                uniqueKeysWithValues: sources.map { (String($0.id), $0) }
            )
            completion(.success(sources.map(Self.presentationItem)))
        } catch {
            sourceByID = [:]
            completion(.failure(error))
        }
    }

    public func requestPermissions(
        completion: @escaping @MainActor (HostPermissionSnapshot) -> Void
    ) {
        requestMicrophoneIfNeeded { [weak self] in
            guard let self else { return }
            self.requestSpeechIfNeeded { [weak self] in
                guard let self else { return }
                completion(self.currentPermissionSnapshot())
            }
        }
    }

    public func currentPermissions() -> HostPermissionSnapshot {
        currentPermissionSnapshot()
    }

    public func intelligenceState() -> HostIntelligenceState {
        switch AppleNegotiationAdvisor.availability {
        case .available:
            .available
        case .appleIntelligenceNotEnabled:
            .appleIntelligenceDisabled
        case .modelNotReady:
            .modelNotReady
        case .deviceNotEligible:
            .deviceNotEligible
        case .unavailable:
            .unavailable
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

        let historyStore: HostCallHistoryStore
        switch historyResult {
        case .success(let store):
            historyStore = store
        case .failure(let error):
            completion(.failure(HostRuntimeDriverError.historyUnavailable(error.localizedDescription)))
            return
        }

        let prepared: HostPreparedCallSession
        do {
            prepared = try historyStore.prepareSession()
        } catch {
            completion(.failure(HostRuntimeDriverError.historyUnavailable(error.localizedDescription)))
            return
        }

        let hud = PrivateHUDWindowController()
        let sessionID = prepared.session.id
        let session = LiveCallHUDSession(
            baseline: prepared.baseline,
            clientFacts: prepared.clientFacts,
            hud: hud,
            onResponseRequest: { [weak self] request in
                guard let self else { return }
                onResponseRequest(request)
                self.analyzeLatest(request)
            },
            onTranscriptTurn: { speaker, text, isFinal in
                guard isFinal else { return }
                try? historyStore.appendTranscriptTurn(
                    sessionID: sessionID,
                    speaker: speaker,
                    text: text,
                    isFinal: true
                )
            }
        )

        activeHUD = hud
        activeSession = session
        session.start(source: source, localeIdentifier: "en-US") { [weak self] result in
            guard let self else { return }
            switch result {
            case .success:
                self.systemAudioState = .authorized
                completion(.success(()))
            case .failure(let error):
                self.activeSession = nil
                self.activeHUD = nil
                completion(.failure(error))
            }
        }
    }

    public func stop() {
        adviceGeneration += 1
        activeSession?.stop()
        activeSession = nil
        activeHUD = nil
    }

    private func analyzeLatest(_ request: ResponseRequest) {
        adviceGeneration += 1
        let generation = adviceGeneration

        Task { [weak self] in
            guard let self else { return }
            do {
                let advice = try await self.advisor.advise(for: request)
                guard self.adviceGeneration == generation,
                      let session = self.activeSession else { return }
                session.applyNegotiationAdvice(advice)
            } catch {
                guard self.adviceGeneration == generation,
                      let session = self.activeSession else { return }
                session.applyNegotiationFailure(Self.message(for: error))
            }
        }
    }

    private func requestMicrophoneIfNeeded(
        completion: @escaping @MainActor () -> Void
    ) {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { _ in
                Task { @MainActor in completion() }
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
            Task { @MainActor in completion() }
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
            systemAudio: systemAudioState
        )
    }

    private static func presentationItem(_ source: AudioProcessSource) -> HostAudioSourceItem {
        HostAudioSourceItem(
            id: String(source.id),
            title: source.title,
            bundleID: source.bundleID,
            isRunningOutput: source.isRunningOutput
        )
    }

    private static func mapMicrophoneStatus(_ status: AVAuthorizationStatus) -> HostPermissionState {
        switch status {
        case .notDetermined: .notDetermined
        case .authorized: .authorized
        case .denied: .denied
        case .restricted: .restricted
        @unknown default: .unavailable
        }
    }

    private static func mapSpeechStatus(_ status: SFSpeechRecognizerAuthorizationStatus) -> HostPermissionState {
        switch status {
        case .notDetermined: .notDetermined
        case .authorized: .authorized
        case .denied: .denied
        case .restricted: .restricted
        @unknown default: .unavailable
        }
    }

    private static func message(for error: Error) -> String {
        if let localized = error as? LocalizedError,
           let description = localized.errorDescription,
           !description.isEmpty {
            return description
        }
        return error.localizedDescription
    }
}

private enum HostRuntimeDriverError: LocalizedError, Sendable {
    case sourceUnavailable
    case runtimeAlreadyActive
    case historyUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .sourceUnavailable:
            "The selected audio process is no longer available. Refresh Audio Processes and try again."
        case .runtimeAlreadyActive:
            "A live SFCall runtime is already active."
        case .historyUnavailable(let message):
            "Local call history is unavailable — \(message)"
        }
    }
}
#endif
