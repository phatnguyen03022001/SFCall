#if os(macOS)
import SFCallCore

public final class LiveCallSessionController {
    private let presentationCoordinator: LiveCallPresentationCoordinator
    private let onHUDUpdate: (PrivateHUDContent) -> Void
    private let onResponseRequest: (ResponseRequest) -> Void

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

    public func ingestRemoteTranscript(_ transcript: AppleSpeechTranscript) {
        publish(presentationCoordinator.ingestRemote(transcript))
    }

    public func ingestMicrophoneTranscript(_ transcript: AppleSpeechTranscript) {
        publish(presentationCoordinator.ingestMicrophone(transcript))
    }

    private func publish(_ update: LiveCallPresentationUpdate) {
        onHUDUpdate(update.hud)
        if let request = update.responseRequest {
            onResponseRequest(request)
        }
    }
}
#endif
