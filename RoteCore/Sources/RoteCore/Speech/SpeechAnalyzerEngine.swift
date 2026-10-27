import Foundation

#if canImport(Speech) && canImport(AVFoundation)
import AVFoundation
import Speech

/// On-device transcription with `SpeechAnalyzer` + `SpeechTranscriber` (§9).
/// Streams microphone audio from `AVAudioEngine`, reports volatile and final
/// text with word timings, and biases recognition toward the poem's words
/// through `AnalysisContext.contextualStrings`.
@available(iOS 26, macOS 26, *)
public actor SpeechAnalyzerEngine: SpeechEngine {
    private var locale: Locale?
    private var transcriber: SpeechTranscriber?
    private var analyzer: SpeechAnalyzer?
    private var audioEngine: AVAudioEngine?
    private var inputContinuation: AsyncStream<AnalyzerInput>.Continuation?
    private var resultsTask: Task<Void, Never>?
    private var vocabulary: [String] = []

    private var finalizedText = ""
    private var finalizedTimings: [WordTiming] = []
    private var volatileText = ""
    private var volatileTimings: [WordTiming] = []
    private var updateContinuation: AsyncStream<SpeechUpdate>.Continuation?

    public init() {}

    // MARK: SpeechEngine

    public func prepare(locale requested: Locale) async throws {
        guard let supported = await SpeechTranscriber.supportedLocale(equivalentTo: requested) else {
            throw SpeechEngineError.localeUnsupported(requested.identifier)
        }
        let module = SpeechTranscriber(locale: supported, preset: .timeIndexedProgressiveTranscription)
        let status = await AssetInventory.status(forModules: [module])
        switch status {
        case .unsupported:
            throw SpeechEngineError.assetsUnavailable(supported.identifier)
        case .installed:
            break
        case .supported, .downloading:
            if let request = try await AssetInventory.assetInstallationRequest(supporting: [module]) {
                try await request.downloadAndInstall()
            }
        @unknown default:
            break
        }
        locale = supported
        transcriber = module
    }

    public func setVocabulary(_ words: [String]) async {
        vocabulary = words
    }

    public func start() async throws -> AsyncStream<SpeechUpdate> {
        guard let transcriber else { throw SpeechEngineError.notPrepared }
        guard await Self.requestMicrophone() else { throw SpeechEngineError.microphoneDenied }

        finalizedText = ""
        finalizedTimings = []
        volatileText = ""
        volatileTimings = []

        let context = AnalysisContext()
        if !vocabulary.isEmpty {
            context.contextualStrings = [.general: vocabulary]
        }
        let (inputStream, inputContinuation) = AsyncStream<AnalyzerInput>.makeStream()
        self.inputContinuation = inputContinuation
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        try await analyzer.setContext(context)
        self.analyzer = analyzer

        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
            throw SpeechEngineError.audioSetupFailed("no compatible audio format")
        }
        try startAudio(format: format, continuation: inputContinuation)
        try await analyzer.start(inputSequence: inputStream)

        let (updates, updateContinuation) = AsyncStream<SpeechUpdate>.makeStream()
        self.updateContinuation = updateContinuation
        resultsTask = Task { [weak self] in
            guard let self else { return }
            do {
                for try await result in transcriber.results {
                    await self.handle(result)
                }
            } catch {
                // Finishing the analyzer ends the sequence; errors surface via stop().
            }
            await self.finishUpdates()
        }
        return updates
    }

    public func stop() async throws -> SpeechResult {
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        inputContinuation?.finish()
        inputContinuation = nil
        try await analyzer?.finalizeAndFinishThroughEndOfInput()
        await resultsTask?.value
        resultsTask = nil
        analyzer = nil
        let text = Self.join(finalizedText, volatileText)
        return SpeechResult(transcript: text, timings: finalizedTimings + volatileTimings)
    }

    // MARK: Results

    private func handle(_ result: SpeechTranscriber.Result) {
        let text = String(result.text.characters)
        let timings = Self.timings(in: result.text)
        if result.isFinal {
            finalizedText = Self.join(finalizedText, text)
            finalizedTimings += timings
            volatileText = ""
            volatileTimings = []
        } else {
            volatileText = text
            volatileTimings = timings
        }
        updateContinuation?.yield(SpeechUpdate(text: Self.join(finalizedText, volatileText), isFinal: result.isFinal,
                                               timings: finalizedTimings + volatileTimings))
    }

    private func finishUpdates() {
        updateContinuation?.finish()
        updateContinuation = nil
    }

    static func join(_ a: String, _ b: String) -> String {
        let l = a.trimmingCharacters(in: .whitespaces), r = b.trimmingCharacters(in: .whitespaces)
        if l.isEmpty { return r }
        if r.isEmpty { return l }
        return l + " " + r
    }

    /// Pulls `audioTimeRange` runs out of the attributed transcript.
    static func timings(in text: AttributedString) -> [WordTiming] {
        var out: [WordTiming] = []
        for run in text.runs {
            guard let range = run.audioTimeRange else { continue }
            let word = String(text[run.range].characters).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !word.isEmpty else { continue }
            out.append(WordTiming(word: word, start: range.start.seconds, end: range.end.seconds))
        }
        return out
    }

    // MARK: Audio

    private func startAudio(format: AVAudioFormat, continuation: AsyncStream<AnalyzerInput>.Continuation) throws {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: .duckOthers)
        try session.setActive(true, options: .notifyOthersOnDeactivation)
        #endif
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0 else { throw SpeechEngineError.audioSetupFailed("no input device") }
        let converter = BufferConverter(from: inputFormat, to: format)
        input.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { buffer, _ in
            if let converted = converter.convert(buffer) {
                continuation.yield(AnalyzerInput(buffer: converted))
            }
        }
        engine.prepare()
        try engine.start()
        audioEngine = engine
    }

    private static func requestMicrophone() async -> Bool {
        await AVAudioApplication.requestRecordPermission()
    }
}

/// Converts tap buffers to the analyzer's format. Used only from the audio tap.
@available(iOS 26, macOS 26, *)
private final class BufferConverter: @unchecked Sendable {
    private let converter: AVAudioConverter?
    private let target: AVAudioFormat
    private let passthrough: Bool

    init(from: AVAudioFormat, to: AVAudioFormat) {
        target = to
        passthrough = from == to
        converter = passthrough ? nil : AVAudioConverter(from: from, to: to)
    }

    func convert(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        if passthrough { return buffer }
        guard let converter else { return nil }
        let ratio = target.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 16
        guard let out = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return nil }
        var consumed = false
        var error: NSError?
        converter.convert(to: out, error: &error) { _, status in
            if consumed {
                status.pointee = .noDataNow
                return nil
            }
            consumed = true
            status.pointee = .haveData
            return buffer
        }
        return error == nil ? out : nil
    }
}
#endif
