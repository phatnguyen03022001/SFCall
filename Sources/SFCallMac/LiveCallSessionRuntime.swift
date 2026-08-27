#if os(macOS)
import AVFoundation
import CoreMedia
import Foundation

public protocol LiveCallRemoteAudioSource: AnyObject {
    func start(
        onAudio: @escaping @Sendable (CMSampleBuffer) -> Void,
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
    func append(sampleBuffer: CMSampleBuffer)
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
        source: CallCaptureSource,
        localeIdentifier: String = "en-US"
    ) -> LiveCallSessionRuntime {
        LiveCallSessionRuntime(
            remoteAudio: ScreenCaptureRemoteAudioSource(source: source),
            microphoneAudio: MicrophoneCapture(),
            remoteSpeech: AppleSpeechTranscriber(localeIdentifier: localeIdentifier),
            microphoneSpeech: AppleSpeechTranscriber(localeIdentifier: localeIdentifier)
        )
    }
}

extension MicrophoneCapture: LiveCallMicrophoneAudioSource {}
extension AppleSpeechTranscriber: LiveCallSpeechTranscribing {}

private final class ScreenCaptureRemoteAudioSource: LiveCallRemoteAudioSource, @unchecked Sendable {
    private let source: CallCaptureSource
    private let capture = ScreenAudioCapture()

    init(source: CallCaptureSource) {
        self.source = source
    }

    func start(
        onAudio: @escaping @Sendable (CMSampleBuffer) -> Void,
        completion: @escaping @Sendable (Error?) -> Void
    ) {
        capture.start(source: source, onAudio: onAudio, completion: completion)
    }

    func stop(completion: (@Sendable () -> Void)?) {
        capture.stop(completion: completion)
    }
}
#endif
