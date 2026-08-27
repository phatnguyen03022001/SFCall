#if os(macOS)
import CoreMedia
import Foundation
import ScreenCaptureKit

public enum ScreenAudioCaptureError: Error {
    case startSuperseded
}

public final class ScreenAudioCapture: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    private let outputQueue = DispatchQueue(label: "SFCall.ScreenAudioCapture")
    private let stateLock = NSLock()
    private var stream: SCStream?
    private var onAudio: (@Sendable (CMSampleBuffer) -> Void)?
    private var pendingFilter: (id: UUID, filter: SCContentFilter)?

    public override init() {
        super.init()
    }

    public func start(
        source: CallCaptureSource,
        onAudio: @escaping @Sendable (CMSampleBuffer) -> Void,
        completion: @escaping @Sendable (Error?) -> Void
    ) {
        let startID = stageFilter(source.filter)

        stop { [weak self] in
            guard let self else { return }
            guard let filter = self.takeStagedFilter(id: startID) else {
                completion(ScreenAudioCaptureError.startSuperseded)
                return
            }

            let configuration = SCStreamConfiguration()
            configuration.capturesAudio = true
            configuration.excludesCurrentProcessAudio = true
            configuration.sampleRate = 16_000
            configuration.channelCount = 1
            configuration.width = 2
            configuration.height = 2
            configuration.minimumFrameInterval = CMTime(value: 1, timescale: 2)
            configuration.queueDepth = 3

            let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
            do {
                try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: outputQueue)
                self.setState(stream: stream, onAudio: onAudio)
                stream.startCapture(completionHandler: completion)
            } catch {
                self.clearState()
                completion(error)
            }
        }
    }

    public func stop(completion: (@Sendable () -> Void)? = nil) {
        guard let activeStream = currentStream() else {
            clearState()
            completion?()
            return
        }

        activeStream.stopCapture { [weak self] _ in
            self?.clearState()
            completion?()
        }
    }

    public func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of outputType: SCStreamOutputType
    ) {
        guard outputType == .audio, sampleBuffer.isValid else { return }
        currentAudioHandler()?(sampleBuffer)
    }

    private func stageFilter(_ filter: SCContentFilter) -> UUID {
        let id = UUID()
        stateLock.lock()
        pendingFilter = (id: id, filter: filter)
        stateLock.unlock()
        return id
    }

    private func takeStagedFilter(id: UUID) -> SCContentFilter? {
        stateLock.lock()
        defer { stateLock.unlock() }
        guard let pendingFilter, pendingFilter.id == id else { return nil }
        self.pendingFilter = nil
        return pendingFilter.filter
    }

    private func setState(
        stream: SCStream,
        onAudio: @escaping @Sendable (CMSampleBuffer) -> Void
    ) {
        stateLock.lock()
        self.stream = stream
        self.onAudio = onAudio
        stateLock.unlock()
    }

    private func clearState() {
        stateLock.lock()
        stream = nil
        onAudio = nil
        stateLock.unlock()
    }

    private func currentStream() -> SCStream? {
        stateLock.lock()
        let current = stream
        stateLock.unlock()
        return current
    }

    private func currentAudioHandler() -> (@Sendable (CMSampleBuffer) -> Void)? {
        stateLock.lock()
        let current = onAudio
        stateLock.unlock()
        return current
    }
}
#endif
