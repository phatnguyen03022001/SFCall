#if os(macOS)
import AVFoundation
import Foundation
import SFCallCore
import SFCallMac
import Speech

public struct NativeSmokeConfiguration: Equatable, Sendable {
    public enum Mode: Equatable, Sendable {
        case list
        case run(pid: pid_t, seconds: Int)
    }

    public let mode: Mode
    public let outputURL: URL

    public init(mode: Mode, outputURL: URL) {
        self.mode = mode
        self.outputURL = outputURL
    }

    public static func parse(_ arguments: [String]) throws -> NativeSmokeConfiguration? {
        guard arguments.contains("--native-smoke-list") || arguments.contains("--native-smoke-pid") else {
            return nil
        }

        guard let output = value(after: "--native-smoke-output", in: arguments), !output.isEmpty else {
            throw NativeSmokeConfigurationError.missingOutput
        }
        let outputURL = URL(fileURLWithPath: output)

        if arguments.contains("--native-smoke-list") {
            guard !arguments.contains("--native-smoke-pid") else {
                throw NativeSmokeConfigurationError.conflictingModes
            }
            return NativeSmokeConfiguration(mode: .list, outputURL: outputURL)
        }

        guard let rawPID = value(after: "--native-smoke-pid", in: arguments),
              let pid = pid_t(rawPID), pid > 0 else {
            throw NativeSmokeConfigurationError.invalidPID
        }
        guard let rawSeconds = value(after: "--native-smoke-seconds", in: arguments),
              let seconds = Int(rawSeconds), (1...300).contains(seconds) else {
            throw NativeSmokeConfigurationError.invalidDuration
        }

        return NativeSmokeConfiguration(
            mode: .run(pid: pid, seconds: seconds),
            outputURL: outputURL
        )
    }

    private static func value(after flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag) else { return nil }
        let valueIndex = arguments.index(after: index)
        guard valueIndex < arguments.endIndex else { return nil }
        return arguments[valueIndex]
    }
}

public enum NativeSmokeConfigurationError: LocalizedError, Sendable {
    case missingOutput
    case conflictingModes
    case invalidPID
    case invalidDuration

    public var errorDescription: String? {
        switch self {
        case .missingOutput:
            "--native-smoke-output is required."
        case .conflictingModes:
            "Choose either --native-smoke-list or --native-smoke-pid, not both."
        case .invalidPID:
            "--native-smoke-pid must be a positive process identifier."
        case .invalidDuration:
            "--native-smoke-seconds must be between 1 and 300."
        }
    }
}

public struct NativeSmokeProcess: Codable, Equatable, Sendable {
    public let pid: pid_t
    public let title: String
    public let bundleID: String?
    public let isRunningOutput: Bool

    public init(pid: pid_t, title: String, bundleID: String?, isRunningOutput: Bool) {
        self.pid = pid
        self.title = title
        self.bundleID = bundleID
        self.isRunningOutput = isRunningOutput
    }
}

public struct NativeSmokeReport: Codable, Equatable, Sendable {
    public var result: String
    public var processes: [NativeSmokeProcess]
    public var microphonePermission: String
    public var speechPermission: String
    public var systemAudioStarted: Bool
    public var runtimeStarted: Bool
    public var remotePCMBufferCount: Int
    public var remotePCMFrameCount: Int
    public var microphonePCMBufferCount: Int
    public var microphonePCMFrameCount: Int
    public var remotePCMSampleRate: Double?
    public var remotePCMChannelCount: Int?
    public var remotePCMCommonFormat: String?
    public var remotePCMInterleaved: Bool?
    public var remotePCMMaxRMS: Double
    public var remotePCMNonSilentBufferCount: Int
    public var microphonePCMSampleRate: Double?
    public var microphonePCMChannelCount: Int?
    public var microphonePCMCommonFormat: String?
    public var microphonePCMInterleaved: Bool?
    public var microphonePCMMaxRMS: Double
    public var microphonePCMNonSilentBufferCount: Int
    public var remoteSpeechTaskState: String
    public var remoteSpeechErrorDomain: String?
    public var remoteSpeechErrorCode: Int?
    public var remoteSpeechErrorMessage: String?
    public var microphoneSpeechTaskState: String
    public var microphoneSpeechErrorDomain: String?
    public var microphoneSpeechErrorCode: Int?
    public var microphoneSpeechErrorMessage: String?
    public var clientPartials: [String]
    public var userPartials: [String]
    public var clientFinals: [String]
    public var userFinals: [String]
    public var clientRequestCount: Int
    public var persistedClientTurns: Int
    public var persistedUserTurns: Int
    public var intelligenceState: String
    public var translatedClientTextVietnamese: String?
    public var riskLevel: String?
    public var confidencePercent: Int?
    public var riskReasonVietnamese: String?
    public var recommendedMoveVietnamese: String?
    public var replyEnglish: String?
    public var replyVietnamese: String?
    public var stopCleanup: Bool
    public var firstFailure: String?

    public init(
        result: String,
        processes: [NativeSmokeProcess] = [],
        microphonePermission: String = "notObserved",
        speechPermission: String = "notObserved",
        systemAudioStarted: Bool = false,
        runtimeStarted: Bool = false,
        remotePCMBufferCount: Int = 0,
        remotePCMFrameCount: Int = 0,
        microphonePCMBufferCount: Int = 0,
        microphonePCMFrameCount: Int = 0,
        remotePCMSampleRate: Double? = nil,
        remotePCMChannelCount: Int? = nil,
        remotePCMCommonFormat: String? = nil,
        remotePCMInterleaved: Bool? = nil,
        remotePCMMaxRMS: Double = 0,
        remotePCMNonSilentBufferCount: Int = 0,
        microphonePCMSampleRate: Double? = nil,
        microphonePCMChannelCount: Int? = nil,
        microphonePCMCommonFormat: String? = nil,
        microphonePCMInterleaved: Bool? = nil,
        microphonePCMMaxRMS: Double = 0,
        microphonePCMNonSilentBufferCount: Int = 0,
        remoteSpeechTaskState: String = "notObserved",
        remoteSpeechErrorDomain: String? = nil,
        remoteSpeechErrorCode: Int? = nil,
        remoteSpeechErrorMessage: String? = nil,
        microphoneSpeechTaskState: String = "notObserved",
        microphoneSpeechErrorDomain: String? = nil,
        microphoneSpeechErrorCode: Int? = nil,
        microphoneSpeechErrorMessage: String? = nil,
        clientPartials: [String] = [],
        userPartials: [String] = [],
        clientFinals: [String] = [],
        userFinals: [String] = [],
        clientRequestCount: Int = 0,
        persistedClientTurns: Int = 0,
        persistedUserTurns: Int = 0,
        intelligenceState: String = "notObserved",
        translatedClientTextVietnamese: String? = nil,
        riskLevel: String? = nil,
        confidencePercent: Int? = nil,
        riskReasonVietnamese: String? = nil,
        recommendedMoveVietnamese: String? = nil,
        replyEnglish: String? = nil,
        replyVietnamese: String? = nil,
        stopCleanup: Bool = false,
        firstFailure: String? = nil
    ) {
        self.result = result
        self.processes = processes
        self.microphonePermission = microphonePermission
        self.speechPermission = speechPermission
        self.systemAudioStarted = systemAudioStarted
        self.runtimeStarted = runtimeStarted
        self.remotePCMBufferCount = remotePCMBufferCount
        self.remotePCMFrameCount = remotePCMFrameCount
        self.microphonePCMBufferCount = microphonePCMBufferCount
        self.microphonePCMFrameCount = microphonePCMFrameCount
        self.remotePCMSampleRate = remotePCMSampleRate
        self.remotePCMChannelCount = remotePCMChannelCount
        self.remotePCMCommonFormat = remotePCMCommonFormat
        self.remotePCMInterleaved = remotePCMInterleaved
        self.remotePCMMaxRMS = remotePCMMaxRMS
        self.remotePCMNonSilentBufferCount = remotePCMNonSilentBufferCount
        self.microphonePCMSampleRate = microphonePCMSampleRate
        self.microphonePCMChannelCount = microphonePCMChannelCount
        self.microphonePCMCommonFormat = microphonePCMCommonFormat
        self.microphonePCMInterleaved = microphonePCMInterleaved
        self.microphonePCMMaxRMS = microphonePCMMaxRMS
        self.microphonePCMNonSilentBufferCount = microphonePCMNonSilentBufferCount
        self.remoteSpeechTaskState = remoteSpeechTaskState
        self.remoteSpeechErrorDomain = remoteSpeechErrorDomain
        self.remoteSpeechErrorCode = remoteSpeechErrorCode
        self.remoteSpeechErrorMessage = remoteSpeechErrorMessage
        self.microphoneSpeechTaskState = microphoneSpeechTaskState
        self.microphoneSpeechErrorDomain = microphoneSpeechErrorDomain
        self.microphoneSpeechErrorCode = microphoneSpeechErrorCode
        self.microphoneSpeechErrorMessage = microphoneSpeechErrorMessage
        self.clientPartials = clientPartials
        self.userPartials = userPartials
        self.clientFinals = clientFinals
        self.userFinals = userFinals
        self.clientRequestCount = clientRequestCount
        self.persistedClientTurns = persistedClientTurns
        self.persistedUserTurns = persistedUserTurns
        self.intelligenceState = intelligenceState
        self.translatedClientTextVietnamese = translatedClientTextVietnamese
        self.riskLevel = riskLevel
        self.confidencePercent = confidencePercent
        self.riskReasonVietnamese = riskReasonVietnamese
        self.recommendedMoveVietnamese = recommendedMoveVietnamese
        self.replyEnglish = replyEnglish
        self.replyVietnamese = replyVietnamese
        self.stopCleanup = stopCleanup
        self.firstFailure = firstFailure
    }

    public func write(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(self)
        try data.write(to: url, options: .atomic)
    }
}

@MainActor
public final class NativeSmokeRunner {
    private let catalog: AudioProcessSourceCatalog
    private let advisor: any NegotiationAdviceProvider
    private let injectedHistoryStore: HostCallHistoryStore?

    public init(
        catalog: AudioProcessSourceCatalog = AudioProcessSourceCatalog(),
        advisor: any NegotiationAdviceProvider = AppleNegotiationAdvisor(),
        historyStore: HostCallHistoryStore? = nil
    ) {
        self.catalog = catalog
        self.advisor = advisor
        self.injectedHistoryStore = historyStore
    }

    public func run(_ configuration: NativeSmokeConfiguration) async -> NativeSmokeReport {
        do {
            let sources = try catalog.load()
            let processes = sources.map(Self.processReport)

            switch configuration.mode {
            case .list:
                return NativeSmokeReport(
                    result: "LIST",
                    processes: processes,
                    intelligenceState: Self.intelligenceState
                )

            case .run(let pid, let seconds):
                guard let source = sources.first(where: { $0.pid == pid }) else {
                    return NativeSmokeReport(
                        result: "RUNTIME_FAIL",
                        processes: processes,
                        intelligenceState: Self.intelligenceState,
                        firstFailure: "Audio process PID \(pid) is unavailable."
                    )
                }
                return await runLive(source: source, seconds: seconds, processes: processes)
            }
        } catch {
            return NativeSmokeReport(
                result: "RUNTIME_FAIL",
                intelligenceState: Self.intelligenceState,
                firstFailure: Self.message(for: error)
            )
        }
    }

    private func runLive(
        source: AudioProcessSource,
        seconds: Int,
        processes: [NativeSmokeProcess]
    ) async -> NativeSmokeReport {
        let permissions = await requestRequiredPermissions()
        guard permissions.microphone == .authorized, permissions.speech == .authorized else {
            return NativeSmokeReport(
                result: "BLOCKED_PERMISSION",
                processes: processes,
                microphonePermission: Self.microphoneText(permissions.microphone),
                speechPermission: Self.speechText(permissions.speech),
                intelligenceState: Self.intelligenceState,
                firstFailure: "Microphone and Speech permissions are required."
            )
        }

        let historyStore: HostCallHistoryStore
        do {
            historyStore = try injectedHistoryStore ?? HostCallHistoryStore()
        } catch {
            return NativeSmokeReport(
                result: "RUNTIME_FAIL",
                processes: processes,
                microphonePermission: "authorized",
                speechPermission: "authorized",
                intelligenceState: Self.intelligenceState,
                firstFailure: "Local history setup failed — \(Self.message(for: error))"
            )
        }

        let prepared: HostPreparedCallSession
        do {
            prepared = try historyStore.prepareSession()
        } catch {
            return NativeSmokeReport(
                result: "RUNTIME_FAIL",
                processes: processes,
                microphonePermission: "authorized",
                speechPermission: "authorized",
                intelligenceState: Self.intelligenceState,
                firstFailure: "Local history setup failed — \(Self.message(for: error))"
            )
        }

        let observation = NativeSmokeObservation()
        let audioDiagnostics = NativeSmokeAudioDiagnostics()
        let hud = NativeSmokeHUD(observation: observation)
        let sessionID = prepared.session.id
        let session = LiveCallHUDSession(
            baseline: prepared.baseline,
            clientFacts: prepared.clientFacts,
            hud: hud,
            onResponseRequest: { [advisor] request in
                observation.clientRequestCount += 1
                observation.adviceGeneration += 1
                let generation = observation.adviceGeneration
                observation.adviceTasks.append(
                    Task { @MainActor in
                        do {
                            let advice = try await advisor.advise(for: request)
                            guard observation.adviceGeneration == generation else { return }
                            observation.latestAdvice = advice
                            observation.adviceFailure = nil
                        } catch {
                            guard observation.adviceGeneration == generation else { return }
                            observation.adviceFailure = Self.message(for: error)
                        }
                    }
                )
            },
            onTranscriptTurn: { [historyStore] speaker, text, isFinal in
                if isFinal {
                    observation.recordFinal(speaker: speaker, text: text)
                    do {
                        try historyStore.appendTranscriptTurn(
                            sessionID: sessionID,
                            speaker: speaker,
                            text: text,
                            isFinal: true
                        )
                    } catch {
                        observation.historyFailure = Self.message(for: error)
                    }
                } else {
                    observation.recordPartial(speaker: speaker, text: text)
                }
            }
        )

        let remoteSpeech = AppleSpeechTranscriber(localeIdentifier: "en-US")
        let microphoneSpeech = AppleSpeechTranscriber(localeIdentifier: "en-US")
        let runtime = LiveCallSessionRuntime(
            remoteAudio: NativeSmokeRemoteAudioProbe(
                source: source,
                diagnostics: audioDiagnostics
            ),
            microphoneAudio: NativeSmokeMicrophoneAudioProbe(
                diagnostics: audioDiagnostics
            ),
            remoteSpeech: remoteSpeech,
            microphoneSpeech: microphoneSpeech
        )

        let started: Bool = await withCheckedContinuation { continuation in
            session.start(runtime: runtime) { result in
                switch result {
                case .success:
                    continuation.resume(returning: true)
                case .failure(let error):
                    observation.startFailure = Self.message(for: error)
                    continuation.resume(returning: false)
                }
            }
        }

        guard started else {
            let remoteSpeechDiagnostics = remoteSpeech.diagnosticSnapshot()
            let microphoneSpeechDiagnostics = microphoneSpeech.diagnosticSnapshot()
            session.stop()
            let audio = audioDiagnostics.snapshot()
            return NativeSmokeReport(
                result: "RUNTIME_FAIL",
                processes: processes,
                microphonePermission: "authorized",
                speechPermission: "authorized",
                remotePCMBufferCount: audio.remoteBufferCount,
                remotePCMFrameCount: audio.remoteFrameCount,
                microphonePCMBufferCount: audio.microphoneBufferCount,
                microphonePCMFrameCount: audio.microphoneFrameCount,
                remotePCMSampleRate: audio.remoteSampleRate,
                remotePCMChannelCount: audio.remoteChannelCount,
                remotePCMCommonFormat: audio.remoteCommonFormat,
                remotePCMInterleaved: audio.remoteInterleaved,
                remotePCMMaxRMS: audio.remoteMaxRMS,
                remotePCMNonSilentBufferCount: audio.remoteNonSilentBufferCount,
                microphonePCMSampleRate: audio.microphoneSampleRate,
                microphonePCMChannelCount: audio.microphoneChannelCount,
                microphonePCMCommonFormat: audio.microphoneCommonFormat,
                microphonePCMInterleaved: audio.microphoneInterleaved,
                microphonePCMMaxRMS: audio.microphoneMaxRMS,
                microphonePCMNonSilentBufferCount: audio.microphoneNonSilentBufferCount,
                remoteSpeechTaskState: remoteSpeechDiagnostics.taskState,
                remoteSpeechErrorDomain: remoteSpeechDiagnostics.errorDomain,
                remoteSpeechErrorCode: remoteSpeechDiagnostics.errorCode,
                remoteSpeechErrorMessage: remoteSpeechDiagnostics.errorMessage,
                microphoneSpeechTaskState: microphoneSpeechDiagnostics.taskState,
                microphoneSpeechErrorDomain: microphoneSpeechDiagnostics.errorDomain,
                microphoneSpeechErrorCode: microphoneSpeechDiagnostics.errorCode,
                microphoneSpeechErrorMessage: microphoneSpeechDiagnostics.errorMessage,
                clientPartials: observation.clientPartials,
                userPartials: observation.userPartials,
                clientFinals: observation.clientFinals,
                userFinals: observation.userFinals,
                intelligenceState: Self.intelligenceState,
                stopCleanup: true,
                firstFailure: observation.startFailure ?? "Runtime start failed."
            )
        }

        try? await Task.sleep(for: .seconds(seconds))
        let remoteSpeechDiagnostics = remoteSpeech.diagnosticSnapshot()
        let microphoneSpeechDiagnostics = microphoneSpeech.diagnosticSnapshot()
        session.stop()
        observation.stopCleanup = true

        for task in observation.adviceTasks {
            await task.value
        }

        let persistedTurns: [TranscriptTurnRecord]
        do {
            persistedTurns = try historyStore.transcriptTurns(for: sessionID)
        } catch {
            observation.historyFailure = Self.message(for: error)
            persistedTurns = []
        }

        let persistedClient = persistedTurns.filter { $0.speaker == .client && $0.isFinal }.count
        let persistedUser = persistedTurns.filter { $0.speaker == .user && $0.isFinal }.count
        let advice = observation.latestAdvice
        let intelligence = Self.intelligenceState
        let audio = audioDiagnostics.snapshot()

        let result: String
        let failure: String?
        if let historyFailure = observation.historyFailure {
            result = "RUNTIME_FAIL"
            failure = "History persistence failed — \(historyFailure)"
        } else if observation.clientFinals.isEmpty || observation.userFinals.isEmpty {
            result = "BLOCKED_INPUT"
            failure = Self.inputFailure(observation: observation, audio: audio)
        } else if intelligence != "available" {
            result = "BLOCKED_INTELLIGENCE"
            failure = observation.adviceFailure ?? "Apple Intelligence is \(intelligence)."
        } else if advice == nil {
            result = "RUNTIME_FAIL"
            failure = observation.adviceFailure ?? "Negotiation advice was not produced for the final CLIENT turn."
        } else {
            result = "PASS"
            failure = nil
        }

        return NativeSmokeReport(
            result: result,
            processes: processes,
            microphonePermission: "authorized",
            speechPermission: "authorized",
            systemAudioStarted: true,
            runtimeStarted: true,
            remotePCMBufferCount: audio.remoteBufferCount,
            remotePCMFrameCount: audio.remoteFrameCount,
            microphonePCMBufferCount: audio.microphoneBufferCount,
            microphonePCMFrameCount: audio.microphoneFrameCount,
            remotePCMSampleRate: audio.remoteSampleRate,
            remotePCMChannelCount: audio.remoteChannelCount,
            remotePCMCommonFormat: audio.remoteCommonFormat,
            remotePCMInterleaved: audio.remoteInterleaved,
            remotePCMMaxRMS: audio.remoteMaxRMS,
            remotePCMNonSilentBufferCount: audio.remoteNonSilentBufferCount,
            microphonePCMSampleRate: audio.microphoneSampleRate,
            microphonePCMChannelCount: audio.microphoneChannelCount,
            microphonePCMCommonFormat: audio.microphoneCommonFormat,
            microphonePCMInterleaved: audio.microphoneInterleaved,
            microphonePCMMaxRMS: audio.microphoneMaxRMS,
            microphonePCMNonSilentBufferCount: audio.microphoneNonSilentBufferCount,
            remoteSpeechTaskState: remoteSpeechDiagnostics.taskState,
            remoteSpeechErrorDomain: remoteSpeechDiagnostics.errorDomain,
            remoteSpeechErrorCode: remoteSpeechDiagnostics.errorCode,
            remoteSpeechErrorMessage: remoteSpeechDiagnostics.errorMessage,
            microphoneSpeechTaskState: microphoneSpeechDiagnostics.taskState,
            microphoneSpeechErrorDomain: microphoneSpeechDiagnostics.errorDomain,
            microphoneSpeechErrorCode: microphoneSpeechDiagnostics.errorCode,
            microphoneSpeechErrorMessage: microphoneSpeechDiagnostics.errorMessage,
            clientPartials: observation.clientPartials,
            userPartials: observation.userPartials,
            clientFinals: observation.clientFinals,
            userFinals: observation.userFinals,
            clientRequestCount: observation.clientRequestCount,
            persistedClientTurns: persistedClient,
            persistedUserTurns: persistedUser,
            intelligenceState: intelligence,
            translatedClientTextVietnamese: advice?.translatedClientTextVietnamese,
            riskLevel: advice?.riskLevel.rawValue,
            confidencePercent: advice?.confidencePercent,
            riskReasonVietnamese: advice?.riskReasonVietnamese,
            recommendedMoveVietnamese: advice?.recommendedMoveVietnamese,
            replyEnglish: advice?.replyEnglish,
            replyVietnamese: advice?.replyVietnamese,
            stopCleanup: observation.stopCleanup,
            firstFailure: failure
        )
    }

    private func requestRequiredPermissions() async -> (
        microphone: AVAuthorizationStatus,
        speech: SFSpeechRecognizerAuthorizationStatus
    ) {
        if AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined {
            await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .audio) { _ in
                    continuation.resume()
                }
            }
        }

        if SFSpeechRecognizer.authorizationStatus() == .notDetermined {
            await withCheckedContinuation { continuation in
                AppleSpeechTranscriber.requestAuthorization { _ in
                    continuation.resume()
                }
            }
        }

        return (
            AVCaptureDevice.authorizationStatus(for: .audio),
            SFSpeechRecognizer.authorizationStatus()
        )
    }

    private static var intelligenceState: String {
        AppleNegotiationAdvisor.availability.displayText
    }

    private static func processReport(_ source: AudioProcessSource) -> NativeSmokeProcess {
        NativeSmokeProcess(
            pid: source.pid,
            title: source.title,
            bundleID: source.bundleID,
            isRunningOutput: source.isRunningOutput
        )
    }

    private static func inputFailure(
        observation: NativeSmokeObservation,
        audio: NativeSmokeAudioSnapshot
    ) -> String {
        if audio.remoteBufferCount == 0 && audio.microphoneBufferCount == 0 {
            return "No PCM buffers reached either Speech input."
        }
        if audio.remoteBufferCount == 0 {
            return "No PCM buffers reached CLIENT Speech from the selected process."
        }
        if audio.microphoneBufferCount == 0 {
            return "No PCM buffers reached USER Speech from the microphone."
        }
        if !observation.clientPartials.isEmpty || !observation.userPartials.isEmpty {
            return "Speech hypotheses were observed, but both required final CLIENT and USER turns were not produced."
        }
        return "PCM buffers reached Speech, but no transcript hypotheses were observed for both required channels."
    }

    private static func microphoneText(_ status: AVAuthorizationStatus) -> String {
        switch status {
        case .notDetermined: "notDetermined"
        case .restricted: "restricted"
        case .denied: "denied"
        case .authorized: "authorized"
        @unknown default: "unknown"
        }
    }

    private static func speechText(_ status: SFSpeechRecognizerAuthorizationStatus) -> String {
        switch status {
        case .notDetermined: "notDetermined"
        case .denied: "denied"
        case .restricted: "restricted"
        case .authorized: "authorized"
        @unknown default: "unknown"
        }
    }

    private static func message(for error: Error) -> String {
        if let localized = error as? LocalizedError,
           let message = localized.errorDescription,
           !message.isEmpty {
            return message
        }
        return error.localizedDescription
    }
}

private struct NativeSmokeAudioSnapshot: Sendable {
    let remoteBufferCount: Int
    let remoteFrameCount: Int
    let remoteSampleRate: Double?
    let remoteChannelCount: Int?
    let remoteCommonFormat: String?
    let remoteInterleaved: Bool?
    let remoteMaxRMS: Double
    let remoteNonSilentBufferCount: Int
    let microphoneBufferCount: Int
    let microphoneFrameCount: Int
    let microphoneSampleRate: Double?
    let microphoneChannelCount: Int?
    let microphoneCommonFormat: String?
    let microphoneInterleaved: Bool?
    let microphoneMaxRMS: Double
    let microphoneNonSilentBufferCount: Int
}

private struct NativeSmokePCMObservation: Sendable {
    let sampleRate: Double
    let channelCount: Int
    let commonFormat: String
    let interleaved: Bool
    let rms: Double
}

private final class NativeSmokeAudioDiagnostics: @unchecked Sendable {
    private static let nonSilentRMSThreshold = 0.0001

    private let lock = NSLock()
    private var remoteBufferCount = 0
    private var remoteFrameCount = 0
    private var remoteSampleRate: Double?
    private var remoteChannelCount: Int?
    private var remoteCommonFormat: String?
    private var remoteInterleaved: Bool?
    private var remoteMaxRMS = 0.0
    private var remoteNonSilentBufferCount = 0
    private var microphoneBufferCount = 0
    private var microphoneFrameCount = 0
    private var microphoneSampleRate: Double?
    private var microphoneChannelCount: Int?
    private var microphoneCommonFormat: String?
    private var microphoneInterleaved: Bool?
    private var microphoneMaxRMS = 0.0
    private var microphoneNonSilentBufferCount = 0

    func recordRemote(_ buffer: AVAudioPCMBuffer) {
        let observation = Self.observe(buffer)
        lock.lock()
        remoteBufferCount += 1
        remoteFrameCount += Int(buffer.frameLength)
        if remoteSampleRate == nil {
            remoteSampleRate = observation.sampleRate
            remoteChannelCount = observation.channelCount
            remoteCommonFormat = observation.commonFormat
            remoteInterleaved = observation.interleaved
        }
        remoteMaxRMS = max(remoteMaxRMS, observation.rms)
        if observation.rms > Self.nonSilentRMSThreshold {
            remoteNonSilentBufferCount += 1
        }
        lock.unlock()
    }

    func recordMicrophone(_ buffer: AVAudioPCMBuffer) {
        let observation = Self.observe(buffer)
        lock.lock()
        microphoneBufferCount += 1
        microphoneFrameCount += Int(buffer.frameLength)
        if microphoneSampleRate == nil {
            microphoneSampleRate = observation.sampleRate
            microphoneChannelCount = observation.channelCount
            microphoneCommonFormat = observation.commonFormat
            microphoneInterleaved = observation.interleaved
        }
        microphoneMaxRMS = max(microphoneMaxRMS, observation.rms)
        if observation.rms > Self.nonSilentRMSThreshold {
            microphoneNonSilentBufferCount += 1
        }
        lock.unlock()
    }

    func snapshot() -> NativeSmokeAudioSnapshot {
        lock.lock()
        let snapshot = NativeSmokeAudioSnapshot(
            remoteBufferCount: remoteBufferCount,
            remoteFrameCount: remoteFrameCount,
            remoteSampleRate: remoteSampleRate,
            remoteChannelCount: remoteChannelCount,
            remoteCommonFormat: remoteCommonFormat,
            remoteInterleaved: remoteInterleaved,
            remoteMaxRMS: remoteMaxRMS,
            remoteNonSilentBufferCount: remoteNonSilentBufferCount,
            microphoneBufferCount: microphoneBufferCount,
            microphoneFrameCount: microphoneFrameCount,
            microphoneSampleRate: microphoneSampleRate,
            microphoneChannelCount: microphoneChannelCount,
            microphoneCommonFormat: microphoneCommonFormat,
            microphoneInterleaved: microphoneInterleaved,
            microphoneMaxRMS: microphoneMaxRMS,
            microphoneNonSilentBufferCount: microphoneNonSilentBufferCount
        )
        lock.unlock()
        return snapshot
    }

    private static func observe(_ buffer: AVAudioPCMBuffer) -> NativeSmokePCMObservation {
        NativeSmokePCMObservation(
            sampleRate: buffer.format.sampleRate,
            channelCount: Int(buffer.format.channelCount),
            commonFormat: commonFormatName(buffer.format.commonFormat),
            interleaved: buffer.format.isInterleaved,
            rms: normalizedRMS(buffer)
        )
    }

    private static func commonFormatName(_ format: AVAudioCommonFormat) -> String {
        switch format {
        case .pcmFormatFloat32: "pcmFormatFloat32"
        case .pcmFormatFloat64: "pcmFormatFloat64"
        case .pcmFormatInt16: "pcmFormatInt16"
        case .pcmFormatInt32: "pcmFormatInt32"
        @unknown default: "unknown"
        }
    }

    private static func normalizedRMS(_ buffer: AVAudioPCMBuffer) -> Double {
        let buffers = UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList)
        var sumSquares = 0.0
        var sampleCount = 0

        switch buffer.format.commonFormat {
        case .pcmFormatFloat32:
            for audioBuffer in buffers {
                guard let data = audioBuffer.mData else { continue }
                let count = Int(audioBuffer.mDataByteSize) / MemoryLayout<Float>.size
                let samples = data.assumingMemoryBound(to: Float.self)
                for index in 0..<count {
                    let value = Double(samples[index])
                    sumSquares += value * value
                }
                sampleCount += count
            }

        case .pcmFormatFloat64:
            for audioBuffer in buffers {
                guard let data = audioBuffer.mData else { continue }
                let count = Int(audioBuffer.mDataByteSize) / MemoryLayout<Double>.size
                let samples = data.assumingMemoryBound(to: Double.self)
                for index in 0..<count {
                    let value = samples[index]
                    sumSquares += value * value
                }
                sampleCount += count
            }

        case .pcmFormatInt16:
            let scale = Double(Int16.max)
            for audioBuffer in buffers {
                guard let data = audioBuffer.mData else { continue }
                let count = Int(audioBuffer.mDataByteSize) / MemoryLayout<Int16>.size
                let samples = data.assumingMemoryBound(to: Int16.self)
                for index in 0..<count {
                    let value = Double(samples[index]) / scale
                    sumSquares += value * value
                }
                sampleCount += count
            }

        case .pcmFormatInt32:
            let scale = Double(Int32.max)
            for audioBuffer in buffers {
                guard let data = audioBuffer.mData else { continue }
                let count = Int(audioBuffer.mDataByteSize) / MemoryLayout<Int32>.size
                let samples = data.assumingMemoryBound(to: Int32.self)
                for index in 0..<count {
                    let value = Double(samples[index]) / scale
                    sumSquares += value * value
                }
                sampleCount += count
            }

        @unknown default:
            return 0
        }

        guard sampleCount > 0 else { return 0 }
        return (sumSquares / Double(sampleCount)).squareRoot()
    }
}

private final class NativeSmokeRemoteAudioProbe: LiveCallRemoteAudioSource {
    private let base: CoreAudioProcessTapCapture
    private let diagnostics: NativeSmokeAudioDiagnostics

    init(source: AudioProcessSource, diagnostics: NativeSmokeAudioDiagnostics) {
        self.base = CoreAudioProcessTapCapture(source: source)
        self.diagnostics = diagnostics
    }

    func start(
        onAudio: @escaping (AVAudioPCMBuffer) -> Void,
        completion: @escaping @Sendable (Error?) -> Void
    ) {
        base.start(
            onAudio: { [diagnostics] buffer in
                diagnostics.recordRemote(buffer)
                onAudio(buffer)
            },
            completion: completion
        )
    }

    func stop(completion: (@Sendable () -> Void)?) {
        base.stop(completion: completion)
    }
}

private final class NativeSmokeMicrophoneAudioProbe: LiveCallMicrophoneAudioSource {
    private let base = MicrophoneCapture()
    private let diagnostics: NativeSmokeAudioDiagnostics

    init(diagnostics: NativeSmokeAudioDiagnostics) {
        self.diagnostics = diagnostics
    }

    func start(onBuffer: @escaping (AVAudioPCMBuffer) -> Void) throws {
        try base.start { [diagnostics] buffer in
            diagnostics.recordMicrophone(buffer)
            onBuffer(buffer)
        }
    }

    func stop() {
        base.stop()
    }
}

@MainActor
private final class NativeSmokeObservation {
    var clientPartials: [String] = []
    var userPartials: [String] = []
    var clientFinals: [String] = []
    var userFinals: [String] = []
    var clientRequestCount = 0
    var adviceGeneration = 0
    var latestAdvice: NegotiationAdvice?
    var adviceFailure: String?
    var historyFailure: String?
    var startFailure: String?
    var stopCleanup = false
    var adviceTasks: [Task<Void, Never>] = []
    var lastHUD = PrivateHUDContent()

    func recordPartial(speaker: TranscriptSpeaker, text: String) {
        guard !text.isEmpty else { return }
        switch speaker {
        case .client:
            appendBounded(text, to: &clientPartials)
        case .user:
            appendBounded(text, to: &userPartials)
        }
    }

    func recordFinal(speaker: TranscriptSpeaker, text: String) {
        guard !text.isEmpty else { return }
        switch speaker {
        case .client:
            clientFinals.append(text)
        case .user:
            userFinals.append(text)
        }
    }

    private func appendBounded(_ text: String, to values: inout [String]) {
        guard values.last != text else { return }
        values.append(text)
        if values.count > 20 {
            values.removeFirst(values.count - 20)
        }
    }
}

@MainActor
private final class NativeSmokeHUD: LiveCallHUDPresenting {
    private let observation: NativeSmokeObservation

    init(observation: NativeSmokeObservation) {
        self.observation = observation
    }

    func show() {}
    func hide() {}

    func update(_ content: PrivateHUDContent) {
        observation.lastHUD = content
    }
}
#endif
