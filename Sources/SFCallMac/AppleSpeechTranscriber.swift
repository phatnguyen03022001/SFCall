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

public struct AppleSpeechDiagnosticSnapshot: Equatable, Sendable {
    public let taskState: String
    public let errorDomain: String?
    public let errorCode: Int?
    public let errorMessage: String?

    public init(
        taskState: String,
        errorDomain: String?,
        errorCode: Int?,
        errorMessage: String?
    ) {
        self.taskState = taskState
        self.errorDomain = errorDomain
        self.errorCode = errorCode
        self.errorMessage = errorMessage
    }
}

public enum AppleSpeechTranscriberError: Error {
    case notAuthorized
    case recognizerUnavailable
    case onDeviceRecognitionUnavailable
}

public final class AppleSpeechTranscriber {
    private let recognizer: SFSpeechRecognizer?
    private let diagnosticsLock = NSLock()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var diagnosticTaskState = "notStarted"
    private var diagnosticErrorDomain: String?
    private var diagnosticErrorCode: Int?
    private var diagnosticErrorMessage: String?

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
        resetDiagnostics()

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = true
        self.request = request

        let recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            if let result {
                self?.recordTaskState(result.isFinal ? "completed" : "running")
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
            } else if let error {
                self?.record(error: error)
                self?.request = nil
                self?.task = nil
            }
        }
        task = recognitionTask
        recordInitialTaskState(Self.taskStateText(recognitionTask.state))
    }

    public func append(sampleBuffer: CMSampleBuffer) {
        request?.appendAudioSampleBuffer(sampleBuffer)
    }

    public func append(pcmBuffer: AVAudioPCMBuffer) {
        request?.append(pcmBuffer)
    }

    public func diagnosticSnapshot() -> AppleSpeechDiagnosticSnapshot {
        diagnosticsLock.lock()
        let snapshot = AppleSpeechDiagnosticSnapshot(
            taskState: diagnosticTaskState,
            errorDomain: diagnosticErrorDomain,
            errorCode: diagnosticErrorCode,
            errorMessage: diagnosticErrorMessage
        )
        diagnosticsLock.unlock()
        return snapshot
    }

    public func stop() {
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
    }

    private func resetDiagnostics() {
        diagnosticsLock.lock()
        diagnosticTaskState = "starting"
        diagnosticErrorDomain = nil
        diagnosticErrorCode = nil
        diagnosticErrorMessage = nil
        diagnosticsLock.unlock()
    }

    private func recordInitialTaskState(_ state: String) {
        diagnosticsLock.lock()
        if diagnosticTaskState == "starting" {
            diagnosticTaskState = state
        }
        diagnosticsLock.unlock()
    }

    private func recordTaskState(_ state: String) {
        diagnosticsLock.lock()
        diagnosticTaskState = state
        diagnosticsLock.unlock()
    }

    private func record(error: Error) {
        let error = error as NSError
        diagnosticsLock.lock()
        diagnosticTaskState = "completed"
        diagnosticErrorDomain = error.domain
        diagnosticErrorCode = error.code
        diagnosticErrorMessage = error.localizedDescription
        diagnosticsLock.unlock()
    }

    private static func taskStateText(_ state: SFSpeechRecognitionTaskState) -> String {
        switch state {
        case .starting: "starting"
        case .running: "running"
        case .finishing: "finishing"
        case .canceling: "canceling"
        case .completed: "completed"
        @unknown default: "unknown"
        }
    }
}
#endif
