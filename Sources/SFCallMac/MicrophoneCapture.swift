#if os(macOS)
import AVFoundation
import Foundation

public final class MicrophoneCapture {
    private let engine = AVAudioEngine()
    private var isRunning = false

    public init() {}

    public func start(onBuffer: @escaping (AVAudioPCMBuffer) -> Void) throws {
        guard !isRunning else { return }

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            onBuffer(buffer)
        }
        engine.prepare()
        try engine.start()
        isRunning = true
    }

    public func stop() {
        guard isRunning else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRunning = false
    }
}
#endif
