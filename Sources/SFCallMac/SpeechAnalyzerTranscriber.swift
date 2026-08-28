#if os(macOS)
import AVFoundation
import Foundation
import Speech

public enum SpeechAnalyzerTranscriberError: Error {
    case unavailable
    case unsupportedLocale
    case missingAudioFormat
    case invalidLifecycle
}

public final class SpeechAnalyzerTranscriber: @unchecked Sendable {
    private let transcriber: SpeechTranscriber
    private let analyzer: SpeechAnalyzer
    private let converter: AnalyzerInputConverter
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
        converter: AnalyzerInputConverter,
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
        let converter = AnalyzerInputConverter(analyzerFormat: analyzerFormat)
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
                // Runtime diagnostics can be added at the adapter boundary if
                // native evidence shows they are needed. Recognition behavior
                // remains fail-closed here.
            }
            self?.resultSequenceEnded()
        }
    }

    public func append(pcmBuffer: AVAudioPCMBuffer) {
        stateLock.lock()
        defer { stateLock.unlock() }

        guard acceptsInput, !didRequestFinish else { return }

        do {
            for input in try converter.convert(pcmBuffer, at: nil) {
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
#endif
