#if os(macOS)
import AVFoundation
import CoreMedia
import Foundation
import Speech

public struct AppleSpeechTranscript: Equatable, Sendable {
    public let text: String
    public let isFinal: Bool

    public init(text: String, isFinal: Bool) {
        self.text = text
        self.isFinal = isFinal
    }
}

public enum AppleSpeechTranscriberError: Error {
    case notAuthorized
    case recognizerUnavailable
    case onDeviceRecognitionUnavailable
}

public final class AppleSpeechTranscriber {
    private let recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    public init(localeIdentifier: String = "en-US") {
        recognizer = SFSpeechRecognizer(locale: Locale(identifier: localeIdentifier))
    }

    public static func requestAuthorization(_ completion: @escaping (SFSpeechRecognizerAuthorizationStatus) -> Void) {
        SFSpeechRecognizer.requestAuthorization(completion)
    }

    public var supportsOnDeviceRecognition: Bool {
        recognizer?.supportsOnDeviceRecognition == true
    }

    public func start(onTranscript: @escaping (AppleSpeechTranscript) -> Void) throws {
        guard SFSpeechRecognizer.authorizationStatus() == .authorized else {
            throw AppleSpeechTranscriberError.notAuthorized
        }
        guard let recognizer, recognizer.isAvailable else {
            throw AppleSpeechTranscriberError.recognizerUnavailable
        }
        guard recognizer.supportsOnDeviceRecognition else {
            throw AppleSpeechTranscriberError.onDeviceRecognitionUnavailable
        }

        stop()

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = true
        self.request = request

        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            if let result {
                onTranscript(
                    AppleSpeechTranscript(
                        text: result.bestTranscription.formattedString,
                        isFinal: result.isFinal
                    )
                )
                if result.isFinal {
                    self?.request = nil
                    self?.task = nil
                }
            } else if error != nil {
                self?.request = nil
                self?.task = nil
            }
        }
    }

    public func append(sampleBuffer: CMSampleBuffer) {
        request?.appendAudioSampleBuffer(sampleBuffer)
    }

    public func append(pcmBuffer: AVAudioPCMBuffer) {
        request?.append(pcmBuffer)
    }

    public func stop() {
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
    }
}
#endif
