#if os(macOS)
import AVFoundation
import Foundation

public protocol LiveCallRemoteAudioSource: AnyObject {
    func start(
        onAudio: @escaping (AVAudioPCMBuffer) -> Void,
        completion: @escaping @Sendable (Error?) -> Void
    )

    func stop(completion: (@Sendable () -> Void)?)
}

public protocol LiveCallMicrophoneAudioSource: AnyObject {
    func start(onBuffer: @escaping (AVAudioPCMBuffer) -> Void) throws
    func stop()
}

public protocol LiveCallSpeechTranscribing: AnyObject {
    func start(onTranscript: @escaping (AppleSpeechTranscript) -> Void) throws
    func append(pcmBuffer: AVAudioPCMBuffer)
    func stop()
}

public final class LiveCallSessionRuntime: @unchecked Sendable {
    let remoteAudio: any LiveCallRemoteAudioSource
    let microphoneAudio: any LiveCallMicrophoneAudioSource
    let remoteSpeech: any LiveCallSpeechTranscribing
    let microphoneSpeech: any LiveCallSpeechTranscribing

    public init(
        remoteAudio: any LiveCallRemoteAudioSource,
        microphoneAudio: any LiveCallMicrophoneAudioSource,
        remoteSpeech: any LiveCallSpeechTranscribing,
        microphoneSpeech: any LiveCallSpeechTranscribing
    ) {
        self.remoteAudio = remoteAudio
        self.microphoneAudio = microphoneAudio
        self.remoteSpeech = remoteSpeech
        self.microphoneSpeech = microphoneSpeech
    }

    public static func native(
        source: AudioProcessSource,
        localeIdentifier: String = "en-US"
    ) -> LiveCallSessionRuntime {
        let coordinator = SingleRecognizerTurnCoordinator(localeIdentifier: localeIdentifier)
        return LiveCallSessionRuntime(
            remoteAudio: CoreAudioProcessTapCapture(source: source),
            microphoneAudio: MicrophoneCapture(),
            remoteSpeech: coordinator.clientEndpoint,
            microphoneSpeech: coordinator.userEndpoint
        )
    }
}

extension MicrophoneCapture: LiveCallMicrophoneAudioSource {}
extension AppleSpeechTranscriber: LiveCallSpeechTranscribing {}
extension CoreAudioProcessTapCapture: LiveCallRemoteAudioSource {}
#endif
