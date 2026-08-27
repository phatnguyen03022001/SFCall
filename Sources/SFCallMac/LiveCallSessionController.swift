#if os(macOS)
import Foundation
import SFCallCore

public final class LiveCallSessionController: @unchecked Sendable {
    private let presentationCoordinator: LiveCallPresentationCoordinator
    private let onHUDUpdate: (PrivateHUDContent) -> Void
    private let onResponseRequest: (ResponseRequest) -> Void
    private let eventLock = NSLock()
    private let runtimeLock = NSLock()
    private var activeRuntime: LiveCallSessionRuntime?

    public init(
        baseline: CaseBaseline,
        clientFacts: [ClientFactRecord],
        onHUDUpdate: @escaping (PrivateHUDContent) -> Void,
        onResponseRequest: @escaping (ResponseRequest) -> Void
    ) {
        self.presentationCoordinator = LiveCallPresentationCoordinator(
            baseline: baseline,
            clientFacts: clientFacts
        )
        self.onHUDUpdate = onHUDUpdate
        self.onResponseRequest = onResponseRequest
    }

    public func start(
        runtime: LiveCallSessionRuntime,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        stop()
        let completionBox = StartCompletionBox(completion)

        do {
            try runtime.remoteSpeech.start { [weak self] transcript in
                self?.ingestRemoteTranscript(transcript)
            }
            try runtime.microphoneSpeech.start { [weak self] transcript in
                self?.ingestMicrophoneTranscript(transcript)
            }
            try runtime.microphoneAudio.start { buffer in
                runtime.microphoneSpeech.append(pcmBuffer: buffer)
            }
        } catch {
            cleanup(runtime)
            completionBox.call(.failure(error))
            return
        }

        setActiveRuntime(runtime)
        runtime.remoteAudio.start(
            onAudio: { sampleBuffer in
                runtime.remoteSpeech.append(sampleBuffer: sampleBuffer)
            },
            completion: { [weak self] error in
                guard let self else { return }
                if let error {
                    self.clearActiveRuntime(runtime)
                    self.cleanup(runtime)
                    completionBox.call(.failure(error))
                } else {
                    completionBox.call(.success(()))
                }
            }
        )
    }

    public func stop() {
        guard let runtime = takeActiveRuntime() else { return }
        cleanup(runtime)
    }

    public func ingestRemoteTranscript(_ transcript: AppleSpeechTranscript) {
        eventLock.lock()
        defer { eventLock.unlock() }
        publish(presentationCoordinator.ingestRemote(transcript))
    }

    public func ingestMicrophoneTranscript(_ transcript: AppleSpeechTranscript) {
        eventLock.lock()
        defer { eventLock.unlock() }
        publish(presentationCoordinator.ingestMicrophone(transcript))
    }

    private func publish(_ update: LiveCallPresentationUpdate) {
        onHUDUpdate(update.hud)
        if let request = update.responseRequest {
            onResponseRequest(request)
        }
    }

    private func cleanup(_ runtime: LiveCallSessionRuntime) {
        runtime.remoteAudio.stop(completion: nil)
        runtime.microphoneAudio.stop()
        runtime.remoteSpeech.stop()
        runtime.microphoneSpeech.stop()
    }

    private func setActiveRuntime(_ runtime: LiveCallSessionRuntime) {
        runtimeLock.lock()
        activeRuntime = runtime
        runtimeLock.unlock()
    }

    private func takeActiveRuntime() -> LiveCallSessionRuntime? {
        runtimeLock.lock()
        let runtime = activeRuntime
        activeRuntime = nil
        runtimeLock.unlock()
        return runtime
    }

    private func clearActiveRuntime(_ runtime: LiveCallSessionRuntime) {
        runtimeLock.lock()
        if activeRuntime === runtime {
            activeRuntime = nil
        }
        runtimeLock.unlock()
    }
}

private final class StartCompletionBox: @unchecked Sendable {
    private let lock = NSLock()
    private var completion: ((Result<Void, Error>) -> Void)?

    init(_ completion: @escaping (Result<Void, Error>) -> Void) {
        self.completion = completion
    }

    func call(_ result: Result<Void, Error>) {
        lock.lock()
        let completion = self.completion
        self.completion = nil
        lock.unlock()
        completion?(result)
    }
}
#endif
