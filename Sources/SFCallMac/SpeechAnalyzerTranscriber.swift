#if os(macOS)
import AVFoundation
import Foundation
import Speech

public enum SpeechAnalyzerTranscriberError: Error {
    case unavailable
    case unsupportedLocale
    case missingAudioFormat
    case invalidLifecycle
    case converterUnavailable
    case conversionFailed
    case inputFormatChanged
}

public final class SpeechAnalyzerTranscriber: @unchecked Sendable {
    private let transcriber: SpeechTranscriber
    private let analyzer: SpeechAnalyzer
    private let converter: SpeechAnalyzerPCMConverter
    private let inputBuilder: AsyncStream<AnalyzerInput>.Continuation
    private let stateLock = NSLock()

    private var onTranscript: ((AppleSpeechTranscript) -> Void)?
    private var resultsTask: Task<Void, Never>?
    private var didStart = false
    private var didRequestFinish = false
    private var acceptsInput = false

    private init(
        transcriber: SpeechTranscriber,
        analyzer: SpeechAnalyzer,
        converter: SpeechAnalyzerPCMConverter,
        inputBuilder: AsyncStream<AnalyzerInput>.Continuation
    ) {
        self.transcriber = transcriber
        self.analyzer = analyzer
        self.converter = converter
        self.inputBuilder = inputBuilder
    }

    public static func prepare(
        localeIdentifier: String = "en-US"
    ) async throws -> SpeechAnalyzerTranscriber {
        guard SpeechTranscriber.isAvailable else {
            throw SpeechAnalyzerTranscriberError.unavailable
        }

        let requestedLocale = Locale(identifier: localeIdentifier)
        guard let locale = await SpeechTranscriber.supportedLocale(
            equivalentTo: requestedLocale
        ) else {
            throw SpeechAnalyzerTranscriberError.unsupportedLocale
        }

        let transcriber = SpeechTranscriber(
            locale: locale,
            preset: .progressiveTranscription
        )

        if let installationRequest = try await AssetInventory.assetInstallationRequest(
            supporting: [transcriber]
        ) {
            try await installationRequest.downloadAndInstall()
        }

        guard let analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(
            compatibleWith: [transcriber]
        ) else {
            throw SpeechAnalyzerTranscriberError.missingAudioFormat
        }

        let analyzer = SpeechAnalyzer(modules: [transcriber])
        let converter = SpeechAnalyzerPCMConverter(analyzerFormat: analyzerFormat)
        let (inputSequence, inputBuilder) = AsyncStream<AnalyzerInput>.makeStream()

        try await analyzer.start(inputSequence: inputSequence)

        return SpeechAnalyzerTranscriber(
            transcriber: transcriber,
            analyzer: analyzer,
            converter: converter,
            inputBuilder: inputBuilder
        )
    }

    public func start(
        onTranscript: @escaping (AppleSpeechTranscript) -> Void
    ) throws {
        stateLock.lock()
        defer { stateLock.unlock() }

        guard !didStart, !didRequestFinish else {
            throw SpeechAnalyzerTranscriberError.invalidLifecycle
        }

        didStart = true
        acceptsInput = true
        self.onTranscript = onTranscript

        let transcriber = self.transcriber
        resultsTask = Task { [weak self, transcriber] in
            do {
                for try await result in transcriber.results {
                    guard !Task.isCancelled else { break }
                    let text = String(result.text.characters)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !text.isEmpty else { continue }
                    self?.deliver(
                        AppleSpeechTranscript(
                            text: text,
                            isFinal: result.isFinal
                        )
                    )
                }
            } catch {
                // Recognition remains fail-closed at this adapter boundary.
            }
            self?.resultSequenceEnded()
        }
    }

    public func append(pcmBuffer: AVAudioPCMBuffer) {
        stateLock.lock()
        defer { stateLock.unlock() }

        guard acceptsInput, !didRequestFinish else { return }

        do {
            for input in try converter.convert(pcmBuffer) {
                inputBuilder.yield(input)
            }
        } catch {
            acceptsInput = false
        }
    }

    public func stop() {
        stateLock.lock()
        guard !didRequestFinish else {
            stateLock.unlock()
            return
        }

        didRequestFinish = true
        acceptsInput = false

        if let inputs = try? converter.flush() {
            for input in inputs {
                inputBuilder.yield(input)
            }
        }
        inputBuilder.finish()
        stateLock.unlock()

        let analyzer = self.analyzer
        Task {
            do {
                try await analyzer.finalizeAndFinishThroughEndOfInput()
            } catch {
                await analyzer.cancelAndFinishNow()
            }
        }
    }

    private func deliver(_ transcript: AppleSpeechTranscript) {
        stateLock.lock()
        let handler = onTranscript
        stateLock.unlock()
        handler?(transcript)
    }

    private func resultSequenceEnded() {
        stateLock.lock()
        onTranscript = nil
        resultsTask = nil
        stateLock.unlock()
    }
}

private final class SpeechAnalyzerPCMConverter {
    private let analyzerFormat: AVAudioFormat
    private var converter: AVAudioConverter?
    private var sourceFormat: AVAudioFormat?

    init(analyzerFormat: AVAudioFormat) {
        self.analyzerFormat = analyzerFormat
    }

    func convert(_ buffer: AVAudioPCMBuffer) throws -> [AnalyzerInput] {
        let converter = try converter(for: buffer.format)
        let outputCapacity = Self.outputCapacity(
            inputFrames: buffer.frameLength,
            inputSampleRate: buffer.format.sampleRate,
            outputSampleRate: analyzerFormat.sampleRate
        )
        guard let outputBuffer = AVAudioPCMBuffer(
            pcmFormat: analyzerFormat,
            frameCapacity: outputCapacity
        ) else {
            throw SpeechAnalyzerTranscriberError.converterUnavailable
        }

        var didProvideInput = false
        var conversionError: NSError?
        let status = converter.convert(
            to: outputBuffer,
            error: &conversionError
        ) { _, inputStatus in
            guard !didProvideInput else {
                inputStatus.pointee = .noDataNow
                return nil
            }
            didProvideInput = true
            inputStatus.pointee = .haveData
            return buffer
        }

        if status == .error || conversionError != nil {
            throw conversionError ?? SpeechAnalyzerTranscriberError.conversionFailed
        }

        guard outputBuffer.frameLength > 0 else { return [] }
        return [AnalyzerInput(buffer: outputBuffer)]
    }

    func flush() throws -> [AnalyzerInput] {
        guard let converter else { return [] }

        var inputs: [AnalyzerInput] = []
        for _ in 0..<8 {
            guard let outputBuffer = AVAudioPCMBuffer(
                pcmFormat: analyzerFormat,
                frameCapacity: 4_096
            ) else {
                throw SpeechAnalyzerTranscriberError.converterUnavailable
            }

            var conversionError: NSError?
            let status = converter.convert(
                to: outputBuffer,
                error: &conversionError
            ) { _, inputStatus in
                inputStatus.pointee = .endOfStream
                return nil
            }

            if status == .error || conversionError != nil {
                throw conversionError ?? SpeechAnalyzerTranscriberError.conversionFailed
            }

            if outputBuffer.frameLength > 0 {
                inputs.append(AnalyzerInput(buffer: outputBuffer))
            }

            if status == .endOfStream || outputBuffer.frameLength == 0 {
                break
            }
        }

        return inputs
    }

    private func converter(for inputFormat: AVAudioFormat) throws -> AVAudioConverter {
        if let converter, let sourceFormat {
            guard Self.sameFormat(sourceFormat, inputFormat) else {
                throw SpeechAnalyzerTranscriberError.inputFormatChanged
            }
            return converter
        }

        guard let converter = AVAudioConverter(
            from: inputFormat,
            to: analyzerFormat
        ) else {
            throw SpeechAnalyzerTranscriberError.converterUnavailable
        }
        self.converter = converter
        sourceFormat = inputFormat
        return converter
    }

    private static func sameFormat(_ lhs: AVAudioFormat, _ rhs: AVAudioFormat) -> Bool {
        lhs.sampleRate == rhs.sampleRate
            && lhs.channelCount == rhs.channelCount
            && lhs.commonFormat == rhs.commonFormat
            && lhs.isInterleaved == rhs.isInterleaved
    }

    private static func outputCapacity(
        inputFrames: AVAudioFrameCount,
        inputSampleRate: Double,
        outputSampleRate: Double
    ) -> AVAudioFrameCount {
        guard inputSampleRate > 0, outputSampleRate > 0 else {
            return max(inputFrames, 1)
        }
        let scaled = ceil(Double(inputFrames) * outputSampleRate / inputSampleRate)
        return AVAudioFrameCount(max(scaled + 64, 1))
    }
}
#endif
