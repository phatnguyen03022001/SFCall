#if os(macOS)
import AVFoundation
import XCTest
@testable import SFCallMac

final class SingleRecognizerTurnSchedulerTests: XCTestCase {
    func testSwitchingSpeakersNeverOverlapsRecognitionTasks() throws {
        let clock = TestClock()
        let factory = FakeRecognitionFactory()
        let coordinator = SingleRecognizerTurnCoordinator(
            engineFactory: { factory.makeEngine() },
            now: { clock.now }
        )
        try start(coordinator)

        sendActiveClientAudio(to: coordinator.clientEndpoint, clock: clock)
        XCTAssertEqual(factory.maximumConcurrentRecognitionTasks, 1)

        clock.advance(by: 0.60)
        sendActiveUserAudio(to: coordinator.userEndpoint, clock: clock)
        XCTAssertEqual(factory.maximumConcurrentRecognitionTasks, 1)
        XCTAssertEqual(factory.engines.first?.gracefulFinishCount, 1)

        factory.engines[0].complete()

        XCTAssertEqual(factory.maximumConcurrentRecognitionTasks, 1)
        XCTAssertEqual(factory.concurrentRecognitionTasks, 1)
        XCTAssertEqual(factory.engines.count, 2)
    }

    func testRoutesClientAndUserTranscriptsToTheirEndpoints() throws {
        let clock = TestClock()
        let factory = FakeRecognitionFactory()
        let coordinator = SingleRecognizerTurnCoordinator(
            engineFactory: { factory.makeEngine() },
            now: { clock.now }
        )
        var clientTranscripts: [AppleSpeechTranscript] = []
        var userTranscripts: [AppleSpeechTranscript] = []
        try coordinator.clientEndpoint.start { clientTranscripts.append($0) }
        try coordinator.userEndpoint.start { userTranscripts.append($0) }

        sendActiveClientAudio(to: coordinator.clientEndpoint, clock: clock)
        factory.engines[0].emit(text: "CLIENT turn", isFinal: false)
        factory.engines[0].emit(text: "CLIENT final", isFinal: true)

        clock.advance(by: 0.60)
        sendActiveUserAudio(to: coordinator.userEndpoint, clock: clock)
        factory.engines[0].complete()
        factory.engines[1].emit(text: "USER turn", isFinal: false)
        factory.engines[1].emit(text: "USER final", isFinal: true)

        XCTAssertEqual(
            clientTranscripts,
            [
                AppleSpeechTranscript(text: "CLIENT turn", isFinal: false),
                AppleSpeechTranscript(text: "CLIENT final", isFinal: true),
            ]
        )
        XCTAssertEqual(
            userTranscripts,
            [
                AppleSpeechTranscript(text: "USER turn", isFinal: false),
                AppleSpeechTranscript(text: "USER final", isFinal: true),
            ]
        )
    }

    func testClientPriorityGracefullyFinishesUserBeforeStartingClient() throws {
        let clock = TestClock()
        let factory = FakeRecognitionFactory()
        let coordinator = SingleRecognizerTurnCoordinator(
            engineFactory: { factory.makeEngine() },
            now: { clock.now }
        )
        try start(coordinator)

        sendActiveUserAudio(to: coordinator.userEndpoint, clock: clock)
        XCTAssertEqual(factory.engines.count, 1)

        sendActiveClientAudio(to: coordinator.clientEndpoint, clock: clock)

        XCTAssertEqual(factory.engines[0].gracefulFinishCount, 1)
        XCTAssertEqual(factory.engines[0].hardStopCount, 0)
        XCTAssertEqual(factory.engines.count, 1)
        XCTAssertEqual(factory.maximumConcurrentRecognitionTasks, 1)

        factory.engines[0].complete()

        XCTAssertEqual(factory.engines.count, 2)
        XCTAssertEqual(factory.concurrentRecognitionTasks, 1)
        XCTAssertEqual(factory.maximumConcurrentRecognitionTasks, 1)
    }

    func testWaitingTurnReplaysOnlyBoundedPreRoll() throws {
        let clock = TestClock()
        let factory = FakeRecognitionFactory()
        let coordinator = SingleRecognizerTurnCoordinator(
            engineFactory: { factory.makeEngine() },
            now: { clock.now }
        )
        try start(coordinator)

        sendActiveClientAudio(to: coordinator.clientEndpoint, clock: clock)
        clock.advance(by: 0.60)
        sendActiveUserAudio(to: coordinator.userEndpoint, clock: clock, amplitudes: [0.01, 0.02])

        clock.advance(by: 0.15)
        coordinator.userEndpoint.append(pcmBuffer: makePCMBuffer(amplitude: 0.03))
        clock.advance(by: 0.15)
        coordinator.userEndpoint.append(pcmBuffer: makePCMBuffer(amplitude: 0.04))
        clock.advance(by: 0.15)
        coordinator.userEndpoint.append(pcmBuffer: makePCMBuffer(amplitude: 0.05))

        factory.engines[0].complete()

        XCTAssertEqual(factory.engines.count, 2)
        XCTAssertEqual(factory.engines[1].receivedAmplitudes, [0.03, 0.04, 0.05])
    }

    func testPreRollOwnsAudioSamplesIndependentOfProducerBufferLifetime() throws {
        let clock = TestClock()
        let factory = FakeRecognitionFactory()
        let coordinator = SingleRecognizerTurnCoordinator(
            engineFactory: { factory.makeEngine() },
            now: { clock.now }
        )
        try start(coordinator)

        sendActiveClientAudio(to: coordinator.clientEndpoint, clock: clock)
        clock.advance(by: 0.60)
        let producerBuffer = makePCMBuffer(amplitude: 0.37)
        coordinator.userEndpoint.append(pcmBuffer: producerBuffer)
        overwriteSamples(in: producerBuffer, with: 0.91)

        clock.advance(by: 0.15)
        coordinator.userEndpoint.append(pcmBuffer: makePCMBuffer(amplitude: 0.38))
        factory.engines[0].complete()

        XCTAssertEqual(factory.engines.count, 2)
        XCTAssertEqual(factory.engines[1].receivedAmplitudes, [0.37, 0.38])
    }

    func testActivityConfirmationResetsAfterReleasedSilence() throws {
        let clock = TestClock()
        let factory = FakeRecognitionFactory()
        let coordinator = SingleRecognizerTurnCoordinator(
            engineFactory: { factory.makeEngine() },
            now: { clock.now }
        )
        try start(coordinator)

        sendActiveClientAudio(to: coordinator.clientEndpoint, clock: clock)
        XCTAssertEqual(factory.engines.count, 1)

        clock.advance(by: 0.60)
        coordinator.clientEndpoint.append(pcmBuffer: makePCMBuffer(amplitude: 0))
        factory.engines[0].complete()

        clock.advance(by: 0.60)
        coordinator.clientEndpoint.append(pcmBuffer: makePCMBuffer(amplitude: 0.10))
        XCTAssertEqual(factory.engines.count, 1)

        clock.advance(by: 0.20)
        coordinator.clientEndpoint.append(pcmBuffer: makePCMBuffer(amplitude: 0.10))
        XCTAssertEqual(factory.engines.count, 2)
    }

    private func start(_ coordinator: SingleRecognizerTurnCoordinator) throws {
        try coordinator.clientEndpoint.start { _ in }
        try coordinator.userEndpoint.start { _ in }
    }

    private func sendActiveClientAudio(
        to endpoint: any LiveCallSpeechTranscribing,
        clock: TestClock,
        amplitudes: [Float] = [0.10, 0.10]
    ) {
        sendActiveAudio(to: endpoint, clock: clock, amplitudes: amplitudes)
    }

    private func sendActiveUserAudio(
        to endpoint: any LiveCallSpeechTranscribing,
        clock: TestClock,
        amplitudes: [Float] = [0.10, 0.10]
    ) {
        sendActiveAudio(to: endpoint, clock: clock, amplitudes: amplitudes)
    }

    private func sendActiveAudio(
        to endpoint: any LiveCallSpeechTranscribing,
        clock: TestClock,
        amplitudes: [Float]
    ) {
        for (index, amplitude) in amplitudes.enumerated() {
            if index > 0 {
                clock.advance(by: 0.15)
            }
            endpoint.append(pcmBuffer: makePCMBuffer(amplitude: amplitude))
        }
    }

    private func makePCMBuffer(amplitude: Float) -> AVAudioPCMBuffer {
        let format = AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1_600)!
        buffer.frameLength = 1_600
        for index in 0 ..< Int(buffer.frameLength) {
            buffer.floatChannelData?[0][index] = amplitude
        }
        return buffer
    }

    private func overwriteSamples(in buffer: AVAudioPCMBuffer, with amplitude: Float) {
        for index in 0 ..< Int(buffer.frameLength) {
            buffer.floatChannelData?[0][index] = amplitude
        }
    }
}

private final class TestClock {
    var now: TimeInterval = 0

    func advance(by duration: TimeInterval) {
        now += duration
    }
}

private final class FakeRecognitionFactory {
    private(set) var engines: [FakeRecognitionEngine] = []
    private(set) var concurrentRecognitionTasks = 0
    private(set) var maximumConcurrentRecognitionTasks = 0

    func makeEngine() -> FakeRecognitionEngine {
        let engine = FakeRecognitionEngine(factory: self)
        engines.append(engine)
        return engine
    }

    func didStartRecognition() {
        concurrentRecognitionTasks += 1
        maximumConcurrentRecognitionTasks = max(
            maximumConcurrentRecognitionTasks,
            concurrentRecognitionTasks
        )
    }

    func didCompleteRecognition() {
        concurrentRecognitionTasks -= 1
    }
}

private final class FakeRecognitionEngine: SingleRecognizerTurnRecognition {
    private let factory: FakeRecognitionFactory
    private var onTranscript: ((AppleSpeechTranscript) -> Void)?
    private var onCompletion: (() -> Void)?
    private(set) var gracefulFinishCount = 0
    private(set) var hardStopCount = 0
    private(set) var receivedAmplitudes: [Float] = []

    init(factory: FakeRecognitionFactory) {
        self.factory = factory
    }

    func start(
        onTranscript: @escaping (AppleSpeechTranscript) -> Void,
        onCompletion: @escaping () -> Void
    ) throws {
        self.onTranscript = onTranscript
        self.onCompletion = onCompletion
        factory.didStartRecognition()
    }

    func append(pcmBuffer: AVAudioPCMBuffer) {
        receivedAmplitudes.append(pcmBuffer.floatChannelData?[0][0] ?? 0)
    }

    func finish(completion: @escaping () -> Void) {
        gracefulFinishCount += 1
        onCompletion = completion
    }

    func stop() {
        hardStopCount += 1
        onTranscript = nil
        onCompletion = nil
    }

    func emit(text: String, isFinal: Bool) {
        onTranscript?(AppleSpeechTranscript(text: text, isFinal: isFinal))
    }

    func complete() {
        factory.didCompleteRecognition()
        onCompletion?()
    }
}
#endif
