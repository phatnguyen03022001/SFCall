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
    ) async throws -> LiveCallSessionRuntime {
        let remoteSpeech = try await SpeechAnalyzerTranscriber.prepare(
            localeIdentifier: localeIdentifier
        )

        let microphoneSpeech: SpeechAnalyzerTranscriber
        do {
            microphoneSpeech = try await SpeechAnalyzerTranscriber.prepare(
                localeIdentifier: localeIdentifier
            )
        } catch {
            remoteSpeech.stop()
            throw error
        }

        return LiveCallSessionRuntime(
            remoteAudio: CoreAudioProcessTapCapture(source: source),
            microphoneAudio: MicrophoneCapture(),
            remoteSpeech: remoteSpeech,
            microphoneSpeech: microphoneSpeech
        )
    }
}

extension MicrophoneCapture: LiveCallMicrophoneAudioSource {}
extension AppleSpeechTranscriber: LiveCallSpeechTranscribing {}
extension SpeechAnalyzerTranscriber: LiveCallSpeechTranscribing {}
extension CoreAudioProcessTapCapture: LiveCallRemoteAudioSource {}
#endif
