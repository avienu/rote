import Foundation

/// One recognized word with its position in the audio, seconds from the start
/// of the recording.
public struct WordTiming: Hashable, Sendable, Codable {
    public var word: String
    public var start: TimeInterval
    public var end: TimeInterval

    public init(word: String, start: TimeInterval, end: TimeInterval) {
        self.word = word
        self.start = start
        self.end = end
    }
}

/// Streaming transcript state. `text` is the whole transcript so far (finalized
/// part plus the current volatile tail).
public struct SpeechUpdate: Hashable, Sendable {
    public var text: String
    public var isFinal: Bool
    public var timings: [WordTiming]

    public init(text: String, isFinal: Bool, timings: [WordTiming] = []) {
        self.text = text
        self.isFinal = isFinal
        self.timings = timings
    }
}

public struct SpeechResult: Hashable, Sendable {
    public var transcript: String
    public var timings: [WordTiming]

    public init(transcript: String, timings: [WordTiming]) {
        self.transcript = transcript
        self.timings = timings
    }
}

public enum SpeechEngineError: Error, Sendable, Equatable {
    case localeUnsupported(String)
    case assetsUnavailable(String)
    case microphoneDenied
    case notPrepared
    case audioSetupFailed(String)
}

/// Speech boundary (§9). `SpeechAnalyzerEngine` is the on-device implementation;
/// tests and development use mocks. ASR output never auto-passes a review.
public protocol SpeechEngine: Sendable {
    /// Triggers an asset download when needed. Throws when the locale cannot be served.
    func prepare(locale: Locale) async throws
    /// Words to bias recognition toward (the poem's vocabulary). No-op if unsupported.
    func setVocabulary(_ words: [String]) async
    func start() async throws -> AsyncStream<SpeechUpdate>
    func stop() async throws -> SpeechResult
}

extension SpeechEngine {
    public func setVocabulary(_ words: [String]) async {}
}
