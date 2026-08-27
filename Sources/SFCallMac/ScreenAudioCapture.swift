#if os(macOS)
import CoreMedia
import Foundation
import ScreenCaptureKit

public final class ScreenAudioCapture: NSObject, SCStreamOutput, SCStreamDelegate {
    private let outputQueue = DispatchQueue(label: "SFCall.ScreenAudioCapture")
    private var stream: SCStream?
    private var onAudio: ((CMSampleBuffer) -> Void)?

    public override init() {
        super.init()
    }

    public func start(
        source: CallCaptureSource,
        onAudio: @escaping (CMSampleBuffer) -> Void,
        completion: @escaping (Error?) -> Void
    ) {
        stop { [weak self] in
            guard let self else { return }

            let configuration = SCStreamConfiguration()
            configuration.capturesAudio = true
            configuration.excludesCurrentProcessAudio = true
            configuration.sampleRate = 16_000
            configuration.channelCount = 1
            configuration.width = 2
            configuration.height = 2
            configuration.minimumFrameInterval = CMTime(value: 1, timescale: 2)
            configuration.queueDepth = 3

            let stream = SCStream(filter: source.filter, configuration: configuration, delegate: self)
            do {
                try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: outputQueue)
                self.onAudio = onAudio
                self.stream = stream
                stream.startCapture(completionHandler: completion)
            } catch {
                self.onAudio = nil
                self.stream = nil
                completion(error)
            }
        }
    }

    public func stop(completion: (() -> Void)? = nil) {
        guard let stream else {
            onAudio = nil
            completion?()
            return
        }

        stream.stopCapture { [weak self] _ in
            self?.stream = nil
            self?.onAudio = nil
            completion?()
        }
    }

    public func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of outputType: SCStreamOutputType
    ) {
        guard outputType == .audio, sampleBuffer.isValid else { return }
        onAudio?(sampleBuffer)
    }
}
#endif
