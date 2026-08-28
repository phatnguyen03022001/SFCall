#if os(macOS)
import AVFoundation
import Foundation

protocol SingleRecognizerTurnRecognition: AnyObject {
    func start(
        onTranscript: @escaping (AppleSpeechTranscript) -> Void,
        onCompletion: @escaping () -> Void
    ) throws
    func append(pcmBuffer: AVAudioPCMBuffer)
    func finish(completion: @escaping () -> Void)
    func stop()
}

extension AppleSpeechTranscriber: SingleRecognizerTurnRecognition {}

final class SingleRecognizerTurnCoordinator: @unchecked Sendable {
    fileprivate enum Speaker {
        case client
        case user
    }

    private struct TimedBuffer {
        let capturedAt: TimeInterval
        let duration: TimeInterval
        let buffer: AVAudioPCMBuffer
    }

    private struct Activity {
        var startedAt: TimeInterval?
        var lastObservedAt: TimeInterval?
    }

    private struct ActiveTurn {
        let speaker: Speaker
        let engine: any SingleRecognizerTurnRecognition
    }

    private static let activityRMS: Float = 0.015
    private static let activityConfirmation: TimeInterval = 0.15
    private static let releaseSilence: TimeInterval = 0.50
    private static let preRollDuration: TimeInterval = 0.30

    private let lock = NSLock()
    private let engineFactory: () -> any SingleRecognizerTurnRecognition
    private let now: () -> TimeInterval
    private var clientTranscript: ((AppleSpeechTranscript) -> Void)?
    private var userTranscript: ((AppleSpeechTranscript) -> Void)?
    private var activity: [Speaker: Activity] = [:]
    private var preRoll: [Speaker: [TimedBuffer]] = [:]
    private var activeTurn: ActiveTurn?
    private var startingSpeaker: Speaker?
    private var finishing = false
    private var waitingSpeaker: Speaker?

    init(
        engineFactory: @escaping () -> any SingleRecognizerTurnRecognition,
        now: @escaping () -> TimeInterval = { Date.timeIntervalSinceReferenceDate }
    ) {
        self.engineFactory = engineFactory
        self.now = now
    }

    convenience init(localeIdentifier: String) {
        self.init(engineFactory: { AppleSpeechTranscriber(localeIdentifier: localeIdentifier) })
    }

    var clientEndpoint: any LiveCallSpeechTranscribing {
        SingleRecognizerTurnEndpoint(coordinator: self, speaker: .client)
    }

    var userEndpoint: any LiveCallSpeechTranscribing {
        SingleRecognizerTurnEndpoint(coordinator: self, speaker: .user)
    }

    fileprivate func start(_ speaker: Speaker, onTranscript: @escaping (AppleSpeechTranscript) -> Void) throws {
        lock.lock()
        switch speaker {
        case .client:
            clientTranscript = onTranscript
        case .user:
            userTranscript = onTranscript
        }
        lock.unlock()
    }

    fileprivate func append(_ buffer: AVAudioPCMBuffer, from speaker: Speaker) {
        let capturedAt = now()
        let isActive = Self.rms(of: buffer) >= Self.activityRMS
        let duration = Self.duration(of: buffer)
        var engineToAppend: (any SingleRecognizerTurnRecognition)?
        var turnToStart: Speaker?
        var turnToFinish: ActiveTurn?

        lock.lock()
        record(buffer, capturedAt: capturedAt, duration: duration, for: speaker)
        if isActive {
            var observed = activity[speaker] ?? Activity()
            if observed.startedAt == nil {
                observed.startedAt = capturedAt
            }
            observed.lastObservedAt = capturedAt
            activity[speaker] = observed
        }

        if let activeTurn, activeTurn.speaker == speaker, !finishing {
            engineToAppend = activeTurn.engine
        }

        if !finishing, activeTurn == nil, startingSpeaker == nil {
            turnToStart = preferredConfirmedSpeaker(at: capturedAt)
            if let turnToStart {
                startingSpeaker = turnToStart
            }
        } else if let activeTurn, !finishing {
            if let waiting = nextSpeaker(after: activeTurn.speaker, at: capturedAt) {
                finishing = true
                waitingSpeaker = waiting
                turnToFinish = activeTurn
            } else if shouldRelease(activeTurn.speaker, at: capturedAt) {
                finishing = true
                waitingSpeaker = nil
                turnToFinish = activeTurn
            }
        }
        lock.unlock()

        engineToAppend?.append(pcmBuffer: buffer)
        if let turnToFinish {
            finish(turnToFinish)
        }
        if let turnToStart {
            startTurn(for: turnToStart)
        }
    }

    func stop() {
        lock.lock()
        let engine = activeTurn?.engine
        activeTurn = nil
        startingSpeaker = nil
        finishing = false
        waitingSpeaker = nil
        clientTranscript = nil
        userTranscript = nil
        activity = [:]
        preRoll = [:]
        lock.unlock()
        engine?.stop()
    }

    private func finish(_ turn: ActiveTurn) {
        turn.engine.finish { [weak self, weak turnEngine = turn.engine] in
            guard let turnEngine else { return }
            self?.didComplete(turnEngine)
        }
    }

    private func startTurn(for speaker: Speaker) {
        let engine = engineFactory()
        do {
            try engine.start(
                onTranscript: { [weak self, weak engine] transcript in
                    guard let engine else { return }
                    self?.route(transcript, from: speaker, engine: engine)
                },
                onCompletion: { [weak self, weak engine] in
                    guard let engine else { return }
                    self?.didComplete(engine)
                }
            )
        } catch {
            lock.lock()
            if startingSpeaker == speaker {
                startingSpeaker = nil
            }
            lock.unlock()
            return
        }

        lock.lock()
        guard startingSpeaker == speaker, activeTurn == nil, !finishing else {
            lock.unlock()
            engine.stop()
            return
        }
        activeTurn = ActiveTurn(speaker: speaker, engine: engine)
        startingSpeaker = nil
        let buffers = preRoll[speaker] ?? []
        lock.unlock()

        for timedBuffer in buffers {
            engine.append(pcmBuffer: timedBuffer.buffer)
        }
    }

    private func route(
        _ transcript: AppleSpeechTranscript,
        from speaker: Speaker,
        engine: any SingleRecognizerTurnRecognition
    ) {
        lock.lock()
        guard activeTurn?.engine === engine else {
            lock.unlock()
            return
        }
        let receiver: ((AppleSpeechTranscript) -> Void)?
        switch speaker {
        case .client:
            receiver = clientTranscript
        case .user:
            receiver = userTranscript
        }
        lock.unlock()
        receiver?(transcript)
    }

    private func didComplete(_ engine: any SingleRecognizerTurnRecognition) {
        var turnToStart: Speaker?

        lock.lock()
        guard activeTurn?.engine === engine else {
            lock.unlock()
            return
        }
        activeTurn = nil
        finishing = false
        turnToStart = waitingSpeaker ?? preferredConfirmedSpeaker(at: now())
        waitingSpeaker = nil
        if let turnToStart {
            startingSpeaker = turnToStart
        }
        lock.unlock()

        if let turnToStart {
            startTurn(for: turnToStart)
        }
    }

    private func record(
        _ buffer: AVAudioPCMBuffer,
        capturedAt: TimeInterval,
        duration: TimeInterval,
        for speaker: Speaker
    ) {
        var buffers = preRoll[speaker] ?? []
        buffers.append(TimedBuffer(capturedAt: capturedAt, duration: duration, buffer: buffer))
        let cutoff = capturedAt - Self.preRollDuration
        buffers.removeAll { $0.capturedAt + $0.duration <= cutoff }
        preRoll[speaker] = buffers
    }

    private func preferredConfirmedSpeaker(at time: TimeInterval) -> Speaker? {
        if isConfirmed(.client, at: time) {
            return .client
        }
        if isConfirmed(.user, at: time) {
            return .user
        }
        return nil
    }

    private func nextSpeaker(after activeSpeaker: Speaker, at time: TimeInterval) -> Speaker? {
        switch activeSpeaker {
        case .client:
            return shouldRelease(.client, at: time) && isConfirmed(.user, at: time) ? .user : nil
        case .user:
            return isConfirmed(.client, at: time) ? .client : nil
        }
    }

    private func isConfirmed(_ speaker: Speaker, at time: TimeInterval) -> Bool {
        guard let observed = activity[speaker],
              let startedAt = observed.startedAt,
              let lastObservedAt = observed.lastObservedAt
        else {
            return false
        }
        return time - startedAt >= Self.activityConfirmation
            && time - lastObservedAt <= Self.releaseSilence
    }

    private func shouldRelease(_ speaker: Speaker, at time: TimeInterval) -> Bool {
        guard let lastObservedAt = activity[speaker]?.lastObservedAt else {
            return true
        }
        return time - lastObservedAt >= Self.releaseSilence
    }

    private static func duration(of buffer: AVAudioPCMBuffer) -> TimeInterval {
        guard buffer.format.sampleRate > 0 else { return 0 }
        return Double(buffer.frameLength) / buffer.format.sampleRate
    }

    private static func rms(of buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData, buffer.frameLength > 0 else {
            return 0
        }
        let channelCount = max(Int(buffer.format.channelCount), 1)
        let sampleCount = Int(buffer.frameLength) * (buffer.format.isInterleaved ? channelCount : 1)
        var sum: Float = 0
        if buffer.format.isInterleaved {
            for index in 0 ..< sampleCount {
                let sample = channelData[0][index]
                sum += sample * sample
            }
            return sqrt(sum / Float(sampleCount))
        }
        for channel in 0 ..< channelCount {
            for index in 0 ..< Int(buffer.frameLength) {
                let sample = channelData[channel][index]
                sum += sample * sample
            }
        }
        return sqrt(sum / Float(Int(buffer.frameLength) * channelCount))
    }
}

private final class SingleRecognizerTurnEndpoint: LiveCallSpeechTranscribing {
    private let coordinator: SingleRecognizerTurnCoordinator
    private let speaker: SingleRecognizerTurnCoordinator.Speaker

    init(coordinator: SingleRecognizerTurnCoordinator, speaker: SingleRecognizerTurnCoordinator.Speaker) {
        self.coordinator = coordinator
        self.speaker = speaker
    }

    func start(onTranscript: @escaping (AppleSpeechTranscript) -> Void) throws {
        try coordinator.start(speaker, onTranscript: onTranscript)
    }

    func append(pcmBuffer: AVAudioPCMBuffer) {
        coordinator.append(pcmBuffer, from: speaker)
    }

    func stop() {
        coordinator.stop()
    }
}
#endif
