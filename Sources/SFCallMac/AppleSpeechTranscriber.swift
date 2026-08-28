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
    private let recognitionLock = NSLock()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var acceptsAudio = false
    private var onTaskCompletion: (() -> Void)?
    private var onGracefulFinish: (() -> Void)?
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
        try start(onTranscript: onTranscript, onCompletion: {})
    }

    func start(
        onTranscript: @escaping (AppleSpeechTranscript) -> Void,
        onCompletion: @escaping () -> Void
    ) throws {
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
        recognitionLock.lock()
        self.request = request
        acceptsAudio = true
        onTaskCompletion = onCompletion
        recognitionLock.unlock()

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
                    self?.completeRecognition()
                }
            } else if let error {
                self?.record(error: error)
                self?.completeRecognition()
            }
        }
        recognitionLock.lock()
        if self.request === request {
            task = recognitionTask
            recognitionLock.unlock()
        } else {
            recognitionLock.unlock()
            recognitionTask.cancel()
        }
        recordInitialTaskState(Self.taskStateText(recognitionTask.state))
    }

    public func append(sampleBuffer: CMSampleBuffer) {
        recognitionLock.lock()
        let request = acceptsAudio ? request : nil
        recognitionLock.unlock()
        request?.appendAudioSampleBuffer(sampleBuffer)
    }

    public func append(pcmBuffer: AVAudioPCMBuffer) {
        recognitionLock.lock()
        let request = acceptsAudio ? request : nil
        recognitionLock.unlock()
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
        recognitionLock.lock()
        let request = self.request
        let task = self.task
        self.request = nil
        self.task = nil
        acceptsAudio = false
        onTaskCompletion = nil
        onGracefulFinish = nil
        recognitionLock.unlock()
        request?.endAudio()
        task?.cancel()
    }

    func finish(completion: @escaping () -> Void) {
        recognitionLock.lock()
        guard let request else {
            recognitionLock.unlock()
            completion()
            return
        }
        let task = self.task
        acceptsAudio = false
        onGracefulFinish = completion
        recognitionLock.unlock()
        request.endAudio()
        task?.finish()
    }

    private func completeRecognition() {
        recognitionLock.lock()
        request = nil
        task = nil
        acceptsAudio = false
        let taskCompletion = onTaskCompletion
        let gracefulFinish = onGracefulFinish
        onTaskCompletion = nil
        onGracefulFinish = nil
        recognitionLock.unlock()
        taskCompletion?()
        gracefulFinish?()
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
